# Candidate manifest schema check

`tools/validate_candidate_manifest.py MANIFEST.tsv ARCHIVES.tsv` checks the two tables against the rules stated in the directory README. It reads metadata only. It opens no font, runs no measurement and says nothing about any font. `tests/test_validate_manifest.py` uses synthetic rows only (`python3 -m unittest discover -s tests`).

Enforced (README states them): the two evidence class names; license value OFL-1.1; SHA-256 fields are 64 lowercase hex digits; pair counts are non-negative integers; URLs are https; a row with no release archive carries a 40-digit commit pin; a written statement names a primary source; structural evidence names its source files; binaries are not stored (no absolute path); each release archive named in a source URL is listed in the archives table; archive rows have a positive size and a SHA-256.

GAP (README is silent, checked for presence only): allowed `status` values (the manifest uses the text "Candidate (sampling-based evaluation)"); `style` vocabulary; `designer` format; `caveats` format; the column names themselves (taken from the manifest header, not from the README); any rule on the number of rows; the unit of the archive size column.

Output lines: `ERROR` or `GAP`, location, field, message, and a summary line. Exit code 1 when any ERROR is found.
