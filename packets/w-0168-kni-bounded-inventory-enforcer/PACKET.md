# GENERIC LAB PACKET P10 - bounded folder inventory + hash re-pin enforcer
Item: drop-in input-safety scanner: walk one folder (no recursion), enforce
explicit budgets, and re-pin every member against a name+hash manifest.
GENERIC piece: synthetic tree only.
Interface: scan.py DIR --manifest M.tsv --max-members N --max-member-bytes B
--max-total-bytes T -> TSV rows "file\tbytes\tsha256\tpin_status(ok|drift)"
+ refusal rows.
Refusals (loud, rc nonzero, named cause): member count / member bytes / total
bytes over budget; unreadable file; manifest row naming a missing file
("manifest_miss"); file present but absent from manifest ("unpinned_member");
hash mismatch ("pin_drift"). Zero members is a VALID empty result, rc 0.
Manifest contract: "file\tsha256" header, 64 lowercase hex; duplicate manifest
row = loud refusal.
Synthetic fixtures: make_fixture.py builds a ~15-file tree with random
(urandom) contents covering each refusal leg + a clean golden pass.
Test command: python3 make_fixture.py /tmp/fx && python3 scan.py /tmp/fx/tree --manifest /tmp/fx/m.tsv --max-members 50 --max-member-bytes 4096 --max-total-bytes 65536 | diff - /tmp/fx/golden.tsv && python3 run_refusal_legs.py /tmp/fx
Target: returned as generic code; the integrator ports it into the product branch.
