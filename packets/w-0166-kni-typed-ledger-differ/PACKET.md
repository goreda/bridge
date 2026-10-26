# GENERIC LAB PACKET P8 - typed key=value ledger differ (before/after support)
Item: drop-in comparator for typed receipt ledgers: text files whose rows are
"name\tkey\tvalue\tkey\tvalue..." (tab-separated, odd column count after name).
GENERIC piece: no product receipts; fixtures are synthetic.
Interface: diff_ledger.py A.txt B.txt -> typed rows:
- "row_changed\t<name>\t<key>\t<old>\t<new>", "row_added\t<name>",
  "row_removed\t<name>", "key_added\t<name>\t<key>", "key_removed\t<name>\t<key>";
- summary row: rows_common, rows_changed, rows_added, rows_removed,
  identical_row_count (explicit, never omitted).
Rules: rows match on the name column; within a row, keys are a SET (key order
inside a row is insignificant); ROW order in the file is insignificant
(shuffle-in = byte-identical out). Duplicate name in one file or duplicate key
in one row = loud refusal (rc nonzero, named).
Synthetic fixtures: make_fixture.py emits two ~20-row ledgers covering every
row type + shuffle + both refusal legs; golden outputs included.
Test command: python3 make_fixture.py /tmp/fx && python3 diff_ledger.py /tmp/fx/a.txt /tmp/fx/b.txt | diff - /tmp/fx/golden.tsv && python3 run_refusal_legs.py /tmp/fx
Target: returned as generic code; the integrator ports it into the product branch.
