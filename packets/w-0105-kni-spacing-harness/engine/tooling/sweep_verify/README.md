# Sweep integrity and record validation

One command runs the sweep audit and validates its record:

    python3 verify.py --root DIR --expected keys.txt --config cfg.json --schema sweep-record.schema.json --out NEW_DIR [--strict]

The output directory must not exist. It receives receipt.txt (the sweepaudit receipt) and record.json (a strict JSON projection of it with mode DESCRIPTIVE ONLY, threshold policy NONE, counts, problem lists and the descriptive complete flag). The record is validated against sweep-record.schema.json (Draft 2020-12, nonfinite JSON refused) and receipt_sha256 is checked against the written receipt.txt. That check is internal consistency with the receipt this tool wrote itself, not proof of external integrity. When validation fails the output directory is still written, for diagnosis. The parent directory of the output directory must exist (it is not created); the config and schema files are read with a strict loader that refuses duplicate keys and nonfinite numbers.

Exit code 0: schema-valid and bound to the receipt. 1: schema or binding failure, or --strict with complete=false. 2: input or file error. A valid record says nothing about sweep content; complete is a flag computed from the lists, not a decision gate. Compatibility with the real sweep writer is UNVERIFIED. Requires jsonschema with the pins in engine/tooling/delivery/requirements-ci.txt; sweepaudit itself stays standard library only.

Tests: python3 -m unittest test_verify
