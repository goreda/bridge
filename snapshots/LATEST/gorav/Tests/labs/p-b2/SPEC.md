# P-B2 Parity Runner - TSV Output Specification

Bridge packet: P-B2 | E2/E4 | lab-b. Clean-room public contract, no private code.

## Scope

`TSVParityRunner` compares two injected `ProbeBackend` adapters on the same
fixture and seek target, and emits a measured TSV document. This first result
ships two fake adapters (`StubProbeBackend`) only. A stub `pass` is evidence
about the runner's diffing and formatting; it is not, and never claims to be,
native engine parity. Native parity requires real adapters, which are pending.

## Document shape

- UTF-8, LF line endings, one header line then exactly one row per backend.
- Row order: `left` backend first, then `right`.
- Every row has exactly 8 tab-separated fields; the file ends with a final LF.
- Header, exactly:
  `fixture<TAB>backend<TAB>frames<TAB>duration_s<TAB>seek_target_s<TAB>seek_landing_s<TAB>av_offset_s<TAB>status`

## Fields

| column | source | format |
| --- | --- | --- |
| fixture | `run(fixture:)` argument, sanitized | text |
| backend | `ProbeBackend.name`, sanitized | text |
| frames | `PlaybackProbe.frames` | decimal integer, or `NA` |
| duration_s | `PlaybackProbe.duration` | round-trip double, or `NA` |
| seek_target_s | `run(seekTo:)` argument (validated finite) | round-trip double |
| seek_landing_s | `PlaybackProbe.seekLanding` | round-trip double, or `NA` |
| av_offset_s | `PlaybackProbe.avOffset` | round-trip double, or `NA` |
| status | comparison result | status token (below) |

## Number formatting

Doubles use Swift's `String(Double)`: locale-independent, always `.` decimal
separator, shortest decimal that `Double(_:)` parses back to the identical bit
pattern (exponent forms such as `1e-07` also round-trip). Never `NaN`/`inf`:
the runner rejects a non-finite seek target up front, and a non-finite
measured value would surface as that token, which is not `NA`. Integers are
plain decimal. A missing value is always `NA`, never `0` and never empty.

## Status vocabulary

- `pass` - both backends measured all four quantities and every value is
  exactly equal (`==` on `Int`/`Double`).
- `different` - both backends measured all four quantities and at least one
  value differs. Both rows carry `different`; each row keeps its own
  backend's values, so the injected difference stays visible.
- `unavailable` - any measured value is missing (`nil`) on either side, or
  the peer backend failed. Never a pass. Rows still print every value that
  was measured; missing ones are `NA`.
- `error(<detail>)` - this backend's `probe` threw. The detail is the
  error's description after field sanitization. All measured columns on that
  row are `NA`; the surviving peer's row is `unavailable`, because parity
  could not be assessed. Errors are explicit in-band; `run` itself throws
  only for invalid runner inputs (non-finite seek target).

Precedence for measured-value comparison: any missing field -> `unavailable`;
else any mismatch -> `different`; else `pass`.

## Field sanitization (escaping)

Applied to `fixture`, `backend`, and the `error(...)` detail. Backslash,
tab, LF, CR become `\\`, `\t`, `\n`, `\r`; other C0 controls and DEL become
`\u{XX}`; all other Unicode scalars pass through unchanged. No emitted row
can contain a raw tab or newline, so a hostile or odd backend name cannot
split a row or add a column.

## Stub fixture JSON

```json
{ "backends": [
  { "name": "stub-a", "result": { "frames": 48, "duration": 2.0,
      "seekLanding": 1.0416666666666667, "avOffset": 0.002 } },
  { "name": "stub-b", "error": "optional failure message" } ] }
```

Exactly two backends per file. Any `result` field may be `null` (missing
measurement). Stubs do not read fixture bytes; the fixture name is passed
through to the TSV only.
