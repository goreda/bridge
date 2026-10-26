# Canonical per-style table builder

Python 3.10 or later, standard library only. All source paths, identities, pool assignments, engine sets, row counts, numeric comparison tolerances and measurement labels are external manifest inputs. No production input is bundled. A table consistency check does not certify source measurement or font lineage.

## Invocation

`python3 canonical_table_build.py --manifest MANIFEST --input-dir INPUT_DIRECTORY --output OUTPUT_TABLE`

The manifest may be outside the input directory. Source paths are relative to the input directory and must resolve inside it. The output is atomically replaced only after successful validation. Exit 2 writes a JSON error with typed code: schema,checksum,row,key,coverage,numeric,mismatch,io. Library callers receive BuildError with ErrorCode. No fallback data, inferred engine, skipped row, rounding, pool borrowing, or silent truncation.

## Input schema

Manifest schema_version is canonical-table-input-v1. Every headed TSV has a schema_version column with that value on every row. Every metadata JSON has the same schema_version. `files` maps source IDs to path,sha256,kind; TSV specifications also carry the exact ordered header. Source hashes bind the raw bytes. Old tables need an explicit external schema migration, not an unversioned implicit adapter.

Required manifest fields: schema_version,numeric_comparison,files,metadata_checks,style_pools,blocks,expected_output_rows. numeric_comparison contains label=CONVENTION,relative_tolerance,absolute_tolerance, both finite and nonnegative. Values are not built into code. style_pools is a list of family/style/pool triples, unique by family/style. No component table defines the pool of another table. A source pool column, if present, must match this assignment.

metadata_checks is a list of file,path bindings. Each path is a literal key list, and either equals_source_sha names a declared source or equals_literal supplies the exact expected value. An empty list is explicit, not an inferred validation grant. Values and hashes are checked; authorship and provenance are not authenticated by a hash.

## Blocks and joins

Three block kinds: frames,perstyle,exclusions. Each contains fields and source_files. fields maps output names to literal strings, {context: key}, or {metadata: [keys]}. Metadata path elements may be {context: engine} to select an engine key. Metadata output values are serialized with str, as in the earlier builder. No expression interpreter or arbitrary code executes. Identity and aggregate fields cannot be overwritten with conflicting bindings.

frames: file,style_column,expected_styles. Source style value must be family|style, exactly two parts, unique. All expected styles are explicit pairs. Input-column bindings supply counts/frame/translation/quantization/etc; none are inferred from family names.

perstyle: join,components,perstyle,metadata_file,engines,expected_styles,rows_per_group,columns,required_values,compare_metrics,fields,engine_fields,source_files,crosschecks. perstyle and metadata_file may be explicit empty strings. Each engine has an engine_fields mapping (empty allowed). Optional style_fields maps family|style to additional output bindings.

join=family_style_engine groups component rows by mapped family/style/engine columns. Perstyle table joins by family/style/engine, unique key; keysets must equal expected_styles×engines. join=engine_metadata supplies family/style via identity and joins component engine with the engine-specific metadata path. Engine lists may differ between blocks, only manifest defines them.

columns maps codepoint,iou and optional nodes/lines/cubics,count or label output names to source headers. Count totals: C2_missing_extrema,C2_stationary_inflections,C7_zero,C7_duplicate,C7_open. Label fields: profile,domain,lineage,node_definition,overall,C1,C3,C4,autotrace_pin,IoU_role. No alias or column name is guessed. Duplicate scalar codepoints per group are rejected, including equivalent hexadecimal spellings. required_values requires exact input-column values. compare_metrics compares specified aggregate and original perstyle fields under the named manifest tolerances. Source perstyle JSON preserves original fields except the new schema_version column.

crosschecks optionally declares file,key=[family,style,engine],engine_column,codepoint_column,iou_column. It checks one existing engine group against a source table with identical scalar keyset and IoU values under the supplied tolerances. It creates no output group. List every crosscheck source in the block's ordered source_files provenance.

exclusions: expected_styles, fields,source_files. Produces one exclusion row per explicit style. Missing pool definition is an error.

Expected output rows must equal sum(frame expected-style counts + perstyle expected-style counts×engine counts + exclusion expected-style counts). This is external configuration, not a fixed production row count. Component rows_per_group is separate from output row count. Example and tests generate synthetic manifests only.

## Output bytes

The 48-field ordered header is FIELDS in source, unchanged from the earlier per-style builder. No output schema column is added. Rows sort lexically by(block,family,style,engine), missing engine is empty. Duplicate sort keys fail. TSV uses UTF-8, no BOM,tab delimiter,LF terminators,csv quoting when required,empty missing fields. No float formatting change: numeric aggregates use Python str(mean/median), count sums use str(integer), all supplied metadata strings preserved. IoU is finite in[0,1], node/count inputs are nonnegative integers. Unicode scalar codepoints exclude surrogate values. No metrics are borrowed across frames or blocks.

source_files and source_sha256 follow manifest source_files order, semicolon-separated. perstyle_source_json uses ensure_ascii=False,sort_keys=True,separators=(',',':'). Raw source header order is bound but JSON key order is canonical. The same manifest and input bytes produce the same output bytes. Changing source row order changes source hashes/provenance even if aggregates match.

## Evidence and limits

Tests use only generated synthetic rows and metadata, no font-derived input.12 synthetic tests passed locally, recorded in synthetic-test-results.txt. No old production output byte comparison or real-data run is claimed. No repository landing performed.

The earlier source uses one engine set for a component comparison and another list including delivered-font controls for an engine-only slice. Their measurement intent is not derived here; generic code supports separately declared engine sets and explicit metadata, without asserting why a particular set was chosen.

## Numeric syntax

Numeric fields accept an optional sign followed by ASCII digits, as integer, integer.fraction or .fraction. Whitespace, underscores, exponents, non-ASCII digits, inf and nan are refused as an invalid number. Count fields accept ASCII unsigned digits only. A syntactically valid value that overflows binary64 is refused as nonfinite. Numeric JSON manifest tokens keep their original text, so an exponent form cannot be normalized into an accepted integer, and string-only bindings still reject them. Booleans are not integers. Computed values stay binary64. Negative zero in a numeric field and integers too large to convert are refused with typed errors.
