# W-0248 install-verify synthetic fixture v1

Runnable synthetic fixture for the W-0248 install/undo/verify lab work. Every
byte is synthetic and generated for this fixture; no real kit content, no real
font, no real user or machine data. The semantics mirror the real 151c
installer exactly; provenance and the validating evidence are in
FIXTURE-CONTRACT.json.

## Layout

- `fixture-package/` - the synthetic update package (delta.json,
  PACKAGE-SEAL.json, qualify-spec.json, payload/, README.txt). id
  `synthetic-9x-demo-001`: 1 add, 3 edits, 1 mode fix (`DEMO.command`).
- `qualified-root/` - a synthetic kit root that the delta's before-map matches:
  KNI-READY.json (placeholder `__FIXTURE_ROOT__`), KNI-VERSION.json,
  HASHES.json, DEMO.command (0644, the mode-fix target), OTHER.command (0755),
  kni/tools/demo_tool.py (v1), instinct-runtime/venv/bin/python3 (executable
  stub), and a kni-bbu journal with one applied transaction
  (`261029-151800-synthetic-tx-applied`, exact nonce `a1b2...f90`) and one
  already-undone transaction (`261029-151700-synthetic-tx-undone`, exact nonce
  `ffee...1100`, changed-only.json plus undone.json and no journal.json).
- `variants/A1..A9` - one defect each, overlay style. `variant.json` names the
  defect, the files to overlay, the invocation and the expected outcome.
- `materialize.py` - copies the base trees, rewrites the placeholder, applies
  one variant overlay. Fixture tooling only, not the installer under test.

## Use

```
python3 materialize.py --dest /tmp/w248run            # happy path
python3 materialize.py --dest /tmp/w248run --variant A5
```

Then point the implementation under test at `/tmp/w248run/fixture-package`
and `/tmp/w248run/qualified-root`. Expected outcomes for every variant,
including the exact refusal evidence validated against the real pinned code,
are in FIXTURE-CONTRACT.json (`variants`). A happy-path apply must report
"3 edits, 1 adds, 1 mode fixes", re-pin KNI-READY via the qualify-produced
candidate (all prior keys preserved), and a happy-path undo of that exact
transaction nonce must restore before bytes, modes and KNI-READY and retain
the added file under the transaction dir.

## Bounds

Synthetic content only. The real installer scripts are not part of this
fixture and are not reimplemented here. Expected outcomes were validated by
the requester against the real pinned code in a requester-side sandbox; labs
must reproduce them with their own implementation under test.
