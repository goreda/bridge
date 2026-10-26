# sweepaudit

Descriptive completeness audit of a sweep output directory. It does not know the record format, applies no thresholds and draws no conclusions about the content of any record.

Inputs: the output directory, the list of expected keys (one font per line), and three caller-supplied rules:
- key regex: maps a relative file path to a key (named group `key`, or the first group);
- result patterns and refusal patterns: `content:REGEX` (default) or `path:REGEX`; a file matching one of them is a record file of that kind;
- optional refusal type regex (group `type` or the first group): a refusal record without a match is listed as untyped.

Per expected key the receipt counts record files and lists: keys with no file, keys with more than one record file, keys with a result and a refusal (or one file matching both), keys that have files but no record file, record or other files whose key is not expected, files without a key, empty files, unreadable files, symlinks (listed, not followed), files read only in part (`--max-read`), files that changed while being audited, expected-list duplicates and a count mismatch against `--expected-count`. Every file gets its size and sha256. `complete=true` only states that every expected key has exactly one record file and none of the lists above has an entry; it is a count, not an approval.

Run: `python -m sweepaudit --root OUT --expected keys.txt --config config.json --receipt receipt.txt [--strict]`
`--strict` makes the exit code 1 when `complete=false`; without it the exit code is 0. Receipt files written inside the audited directory must be excluded with `exclude_regex`.
Tests: `python -m unittest discover -s tests`. Standard library only.

## Layout options

- `key_from_expected`: the key of a path is the longest expected key that prefixes it and is followed by `.`, `-` or `/`. Use it when keys are prefixes of each other or when files of a sweep carry no key.
- `sweep_level_regex`: files that belong to the sweep and not to one key. They are listed under `sweep_level`.
- `empty_ok_regex`: files that are empty by design (for example completion markers). They are not listed as empty.
- `required_templates`: per key that has a record file, each template (with `{key}`) names a file that should exist. Missing ones are listed under `required_missing`.
- `tsv_checks`: per matching tab separated file, counts rows, refusal rows (label column equal to the refusal value, a literal such as `empty`; an empty string is also possible), refusal rows without a note, refusal rows with a non-empty metric, and non-refusal rows with an empty metric. Lines starting with `#` are skipped.

`example-config.json` is written for the layout of the font sweep: a `.done` file is the record of a font, refusals are rows inside `glyphs.tsv`.
- `required_exceptions`: maps a template to the keys for which that file is not expected (for example fonts that are used as static files). Listed under `required_exception`.
- `pair_checks`: byte equality of two copies. `a_regex` has named groups, `b_template` is filled from them (for example `{key}-out-b/{rest}`), optional `b_regex` selects the b files so that b files without an a file are listed. Each pair is compared byte for byte and both sha256 values are written. Lists: `pair_differ`, `pair_b_missing`, `pair_b_without_a`. Without this option the receipt has no pair lines.

## Receipt safety and completeness

- One receipt line is one line: control characters, unpaired surrogates (undecodable file names) and other non-printable characters are written as `\xNN`, `\uNNNN` or `\UNNNNNNNN` escapes.
- A directory that cannot be listed is a typed `unreadable_dir` entry and `complete=false`. A symlinked directory is counted under `symlinks` (kind `symlink_dir`), its contents are not scanned, and `complete=false`.
- `key_from_expected` needs at least one template starting with `{key}` in `required_templates` or `allowed_templates`; otherwise the run is an input error (exit 2). The config file is read with a strict loader that refuses duplicate keys and nonfinite numbers. The `files total` line counts files, symlinked files and symlinked directories, and the classes keyed (readable, keyed, not sweep-level), unkeyed, sweep_level, unreadable_files (unreadable files) and symlinks are disjoint and add up to the total.
- With `key_from_expected`, `required_templates` and `allowed_templates` list the file names that may follow a key. A keyed file whose remainder is none of them is listed as `unexpected_file` (kind `unexpected_suffix`) and `complete=false`.
- A root that is missing or cannot be listed, an expected list that is not UTF-8, and a config that does not parse are input errors: message on stderr, exit code 2. A leading BOM is removed from the expected list (the list hash is still over the bytes as read) and from the config.
- `complete=true` needs: no missing, doubled, conflicting or unclassified keys, no unexpected keys or files, no unkeyed, empty, truncated, unreadable, changed or symlinked entries, no required file missing, no pair difference, and a matching expected count.
- `config_sha256` is the hash of the canonical JSON of the effective config (file and command line options together).

## Pattern limits and table anomalies

- Every pattern match has a wall-clock limit (`pattern_timeout_seconds`, default 2.0, a CONVENTION value, set with `setitimer`, POSIX main thread only; where that is not available the audit refuses to run with an input error). A match that takes longer is listed as `pattern_timeout` (file kind `pattern_timeout`), the run goes on, nothing is truncated or sampled, and `complete=false`.
- `tsv_checks` anomalies are listed under `tsv_anomaly` and block `complete`: `header_missing`, `missing_columns`, `duplicate_header`, `refusal_without_note`, `refusal_with_metric`, `non_refusal_empty_metric`, `short_rows`, `long_rows`, `metric_invalid`, `hash_lines_skipped`. Lines that start with `#` are skipped and counted (`skipped_hash_lines`).
- A filled metric cell must be a finite ASCII decimal number (`[+-]digits[.digits]` or `.digits`); spaces only, NaN, text and exponent forms are `metric_invalid`. The refusal label is compared case-sensitively.
- `required_exceptions` entries that match no required template, name a key that is not in the expected list, or name a key without a record file are listed as `unmatched_exception` and block `complete`.
- A key never extends across `/`: `a/b.done` is not attributed to key `a`.
- `max_read` below 1, a non-positive `pattern_timeout_seconds` and unknown config keys are input errors (exit code 2).
