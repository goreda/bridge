# name-gate fixture

`defective-shipped-name.otf` is a minimal, well-formed sfnt whose `name` table
carries the defective naming the name-table readback gate in
`pipeline/src/main.rs` (`name_table_readback`) exists to reject:

- nameID 1 (family): `Marq Alternate KNI`
- nameID 2 (subfamily): `Regular`
- nameID 4 (full name): `Marq Alternate KNI Regular`
- nameID 6 (PostScript): `MarqAlternateKNI-Regular`

The gate parses only the sfnt offset-table directory and the `name` table, so a
minimal container exercises it exactly; the file is still a valid sfnt (correct
directory, checksum, and UTF-16BE platform-3 records), verified to parse with
fontTools. The original defective delivery binary was never committed anywhere;
this fixture reconstructs the relevant payload deterministically.

## Regenerating

```
python3 build_name_gate_fixture.py defective-shipped-name.otf
```

The script prints the sha256 of the bytes it wrote. That digest is pinned in
`pipeline/src/main.rs` (`name_gate_tests::FIXTURE_SHA256`); the bytes, the
script, and the pin must move together. Current pin:
`e37d7646143ccfe6b8da3c39a18124e1330c09ebebb525b6afad643d0b476d19`

## Resolution order

The tests look for the fixture at, in order:

1. `$KNI_NAME_GATE_FIXTURE` (explicit file path)
2. `$KNI_G_FIXTURES/name_gate/defective-shipped-name.otf`
3. the repo path (this directory)

See `docs/testing-fixtures.md`.
