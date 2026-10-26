//! Shape guard for the verified-row table. A row is one font (by sha256) and
//! one glyph pair. The row records the output font's measured wall-to-wall gap
//! (`gap_after`, taken on the output outline after shaping with the kern
//! applied) and the reference model's gap for the same pair (`gap_target`).
//! VERIFIED means both evidences exist and |gap_after - gap_target| <= tol;
//! FAIL means both exist and the tolerance is exceeded; n/a means one evidence
//! is missing, with a typed reason. n/a is never written as 0 or pass. The
//! guard checks that each row's status agrees with its own numbers and refuses
//! the table otherwise. Every comparison is exact: decimal text is parsed to a
//! scaled i128 integer, never to a float, and equality at the tolerance is
//! VERIFIED. When a value or an aligned intermediate leaves the i128 range the
//! table is refused with an "overflow" error; nothing is rounded. Rows must be
//! in strictly increasing byte order of (font_sha256, left, right). The
//! manifest carries the tolerance and flatten entries (class CONVENTION, unit
//! font_units, written derivation); no tolerance value is held in code.

use std::collections::BTreeMap;
use std::num::NonZeroU32;

/// FORMAT: a sha256 digest is 32 bytes, written as 64 hex characters.
const SHA_HEX_LEN: usize = 64;
/// FORMAT: radix of the decimal text the exact parser reads.
const RADIX: i128 = 10;
const OVERFLOW: &str = "overflow: exact decimal arithmetic left the i128 range";
const COLUMNS: [&str; 16] = [
    "font_sha256", "left", "right", "outline_source", "outline_sha256", "upm", "gap_after", "gap_target", "y_lo",
    "y_hi", "error_bound_method", "error_bound_value", "tol", "tolerance_label", "status", "reason",
];
const NCOL: usize = COLUMNS.len();
const MANIFEST_COLUMNS: [&str; 7] = ["name", "label", "class", "unit", "method", "value", "derivation"];
const ERROR_METHODS: [&str; 2] = ["analytic_root_solve", "flatten"];
const NMAN: usize = MANIFEST_COLUMNS.len();
const OUTLINE_SOURCES: [&str; 2] = ["extract_quadratic", "extract_cff"];
const NA_REASONS: [&str; 5] = [
    "no_vertical_overlap", "missing_wall_evidence", "missing_outline_evidence", "tolerance_missing", "numerical_unresolved",
];
const UNIT: &str = "font_units";
const NA: &str = "n/a";

/// An exact decimal: `mant` / RADIX^`scale`.
#[derive(Clone, Copy)]
struct Dec {
    mant: i128,
    scale: u32,
}

struct Manifest {
    /// (name, label) -> (method, value); name is "tolerance" (error bound) or "flatten" (the parameter).
    entries: BTreeMap<(String, String), (String, Dec)>,
}

fn is_sha(s: &str) -> bool {
    s.len() == SHA_HEX_LEN && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Grammar: -?[0-9]+(\.[0-9]+)?  (ASCII digits only; no exponent, plus sign,
/// leading dot, underscore, space or non-ASCII digit).
fn parse_dec(s: &str) -> Result<Dec, String> {
    let body = s.strip_prefix('-').unwrap_or(s);
    let (int, frac) = body.split_once('.').unwrap_or((body, ""));
    let dot_without_digits = body.contains('.') && frac.is_empty();
    let all_digits = |t: &str| t.bytes().all(|b| b.is_ascii_digit());
    if int.is_empty() || !all_digits(int) || !all_digits(frac) || dot_without_digits {
        return Err(format!("not a plain decimal: {s:?}"));
    }
    let mut mant: i128 = 0;
    for b in int.bytes().chain(frac.bytes()) {
        mant = mant
            .checked_mul(RADIX)
            .and_then(|m| m.checked_add(i128::from(b - b'0')))
            .ok_or_else(|| OVERFLOW.to_string())?;
    }
    if s.starts_with('-') {
        mant = -mant;
    }
    let scale = u32::try_from(frac.len()).map_err(|_| OVERFLOW.to_string())?;
    Ok(Dec { mant, scale })
}

/// Brings the operands to their common scale as exact integers.
fn align_all<const N: usize>(ds: [Dec; N]) -> Result<[i128; N], String> {
    let common = ds.iter().map(|d| d.scale).max().unwrap_or(0);
    let mut out = [0i128; N];
    for (o, d) in out.iter_mut().zip(ds) {
        let factor = RADIX.checked_pow(common - d.scale).ok_or_else(|| OVERFLOW.to_string())?;
        *o = d.mant.checked_mul(factor).ok_or_else(|| OVERFLOW.to_string())?;
    }
    Ok(out)
}

fn leq(a: Dec, b: Dec) -> Result<bool, String> {
    let [x, y] = align_all([a, b])?;
    Ok(x <= y)
}

/// |a - b| <= tol, exactly.
fn within(a: Dec, b: Dec, tol: Dec) -> Result<bool, String> {
    let [x, y, z] = align_all([a, b, tol])?;
    let diff = x.checked_sub(y).and_then(i128::checked_abs).ok_or_else(|| OVERFLOW.to_string())?;
    Ok(diff <= z)
}

fn is_positive(d: Dec) -> bool {
    d.mant > 0
}

fn parse_manifest(text: &str) -> Result<Manifest, String> {
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let header: Vec<&str> = lines.next().map(|h| h.split('\t').collect()).unwrap_or_default();
    if header != MANIFEST_COLUMNS {
        return Err("manifest: bad header".into());
    }
    let mut entries = BTreeMap::new();
    for (i, l) in lines.enumerate() {
        let n = i + 1;
        let f: Vec<&str> = l.split('\t').collect();
        let [name, label, class, unit, method, value, derivation] = <[&str; NMAN]>::try_from(f.as_slice())
            .map_err(|_| format!("manifest row {n}: wrong field count"))?;
        if f.iter().any(|x| x.trim().is_empty()) {
            return Err(format!("manifest row {n}: every field required"));
        }
        if name != "tolerance" && name != "flatten" {
            return Err(format!("manifest row {n}: unknown name"));
        }
        if class != "CONVENTION" {
            return Err(format!("manifest row {n}: class must be CONVENTION"));
        }
        if name == "tolerance" && (unit != UNIT || !ERROR_METHODS.contains(&method)) {
            return Err(format!("manifest row {n}: tolerance needs unit {UNIT} and a known error-bound method"));
        }
        if name == "flatten" && method != "flatten" {
            return Err(format!("manifest row {n}: flatten entry method must be flatten"));
        }
        let v = match parse_dec(value) {
            Ok(v) if is_positive(v) => v,
            Ok(_) => return Err(format!("manifest row {n}: value must be a positive decimal")),
            Err(e) => return Err(format!("manifest row {n}: value: {e}")),
        };
        let _ = derivation;
        if entries.insert((name.to_string(), label.to_string()), (method.to_string(), v)).is_some() {
            return Err(format!("manifest row {n}: duplicate entry"));
        }
    }
    Ok(Manifest { entries })
}

/// Returns (VERIFIED, FAIL, n/a) counts or the first error.
fn check_rows(text: &str, manifest: &Manifest) -> Result<(usize, usize, usize), String> {
    let mut lines = text.lines();
    let header: Vec<&str> = lines.next().map(|h| h.split('\t').collect()).unwrap_or_default();
    if header != COLUMNS {
        return Err("rows: header must be exactly the declared columns".into());
    }
    let has_flatten = manifest.entries.keys().any(|(n, _)| n == "flatten");
    let mut previous: Option<(&str, &str, &str)> = None;
    let mut upm_of_font: BTreeMap<&str, u32> = BTreeMap::new();
    let (mut verified, mut failed, mut na) = (0usize, 0usize, 0usize);
    for (i, l) in lines.enumerate() {
        let n = i + 1;
        let f: Vec<&str> = l.split('\t').collect();
        let [font, left, right, osrc, osha, upm, after, target, y_lo, y_hi, bound_method, bound, tol, label, status, reason] =
            <[&str; NCOL]>::try_from(f.as_slice()).map_err(|_| format!("row {n}: wrong field count"))?;
        if !is_sha(font) {
            return Err(format!("row {n}: font_sha256 must be lowercase hex"));
        }
        if left.is_empty() || right.is_empty() {
            return Err(format!("row {n}: empty glyph name"));
        }
        let key = (font, left, right);
        if let Some(p) = previous {
            if key == p {
                return Err(format!("row {n}: duplicate row for font and pair"));
            }
            if key < p {
                return Err(format!("row {n}: rows must be in strictly increasing byte order of font_sha256, left, right"));
            }
        }
        previous = Some(key);
        let have_outline = OUTLINE_SOURCES.contains(&osrc) && is_sha(osha);
        match status {
            "VERIFIED" | "FAIL" => {
                if !have_outline {
                    return Err(format!("row {n}: {status} row needs outline_source and outline_sha256"));
                }
                let upm_parsed = if !upm.is_empty() && upm.bytes().all(|b| b.is_ascii_digit()) {
                    upm.parse::<NonZeroU32>().ok()
                } else {
                    None
                };
                let upm_value = match upm_parsed {
                    Some(u) => u.get(),
                    None => return Err(format!("row {n}: upm must be a positive integer")),
                };
                if let Some(seen) = upm_of_font.insert(font, upm_value) {
                    if seen != upm_value {
                        return Err(format!("row {n}: the same font_sha256 carries two different upm values"));
                    }
                }
                let dec = |c: &str, s: &str| parse_dec(s).map_err(|e| format!("row {n}: {c}: {e}"));
                let ctx = |e: String| format!("row {n}: {e}");
                let a = dec("gap_after", after)?;
                let t = dec("gap_target", target)?;
                let lo = dec("y_lo", y_lo)?;
                let hi = dec("y_hi", y_hi)?;
                let eb = dec("error_bound_value", bound)?;
                let e = dec("tol", tol)?;
                if !leq(lo, hi).map_err(ctx)? {
                    return Err(format!("row {n}: y_lo must not exceed y_hi"));
                }
                if !is_positive(eb) {
                    return Err(format!("row {n}: error_bound must be positive; zero is never assumed"));
                }
                let entry = match manifest.entries.get(&("tolerance".to_string(), label.to_string())) {
                    Some(e) => e,
                    None => return Err(format!("row {n}: tolerance_label not in the manifest")),
                };
                if bound_method != entry.0 {
                    return Err(format!("row {n}: error_bound_method differs from the manifest method"));
                }
                if !leq(eb, entry.1).map_err(ctx)? {
                    return Err(format!("row {n}: error_bound exceeds the manifest bound"));
                }
                if !leq(eb, e).map_err(ctx)? {
                    return Err(format!("row {n}: tol must cover the error bound"));
                }
                if entry.0 == "flatten" && !has_flatten {
                    return Err(format!("row {n}: flatten method needs a flatten entry in the manifest"));
                }
                if !reason.is_empty() {
                    return Err(format!("row {n}: {status} row carries no reason"));
                }
                let want = if within(a, t, e).map_err(ctx)? { "VERIFIED" } else { "FAIL" };
                if status != want {
                    return Err(format!("row {n}: status {status} contradicts the measurement ({want})"));
                }
                if status == "VERIFIED" {
                    verified += 1;
                } else {
                    failed += 1;
                }
            }
            "n/a" => {
                for (c, v) in [
                    ("upm", upm), ("gap_after", after), ("gap_target", target), ("y_lo", y_lo), ("y_hi", y_hi),
                    ("error_bound_method", bound_method), ("error_bound_value", bound), ("tol", tol),
                    ("tolerance_label", label),
                ] {
                    if v != NA {
                        return Err(format!("row {n}: n/a row must hold exactly n/a in {c}"));
                    }
                }
                if !have_outline && !(osrc == NA && osha == NA) {
                    return Err(format!("row {n}: n/a row outline columns must both be real or both n/a"));
                }
                if !NA_REASONS.contains(&reason) {
                    return Err(format!("row {n}: n/a row needs a typed reason"));
                }
                if reason == "missing_outline_evidence" && have_outline {
                    return Err(format!("row {n}: missing_outline_evidence contradicts the outline columns"));
                }
                if reason == "no_vertical_overlap" && !have_outline {
                    return Err(format!("row {n}: no_vertical_overlap needs an outline"));
                }
                na += 1;
            }
            _ => return Err(format!("row {n}: status must be VERIFIED, FAIL or n/a")),
        }
    }
    Ok((verified, failed, na))
}

const MH: &str = "name\tlabel\tclass\tunit\tmethod\tvalue\tderivation\n";
const MANIFEST: &str = "name\tlabel\tclass\tunit\tmethod\tvalue\tderivation\n\
    tolerance\twall_tol\tCONVENTION\tfont_units\tanalytic_root_solve\t0.25\twritten derivation\n";
const MANIFEST_FLAT: &str = "name\tlabel\tclass\tunit\tmethod\tvalue\tderivation\n\
    tolerance\twall_tol\tCONVENTION\tfont_units\tflatten\t0.25\twritten derivation\n\
    flatten\tflat\tCONVENTION\tfont_units\tflatten\t4\twritten derivation\n";

fn font_a() -> String {
    "a".repeat(SHA_HEX_LEN)
}
fn font_b() -> String {
    "b".repeat(SHA_HEX_LEN)
}

/// Builds a row from the named fields in column order.
fn row(f: [&str; NCOL]) -> String {
    f.join("\t")
}
fn na_row(right: &str, reason: &str) -> String {
    row([&font_a(), "A", right, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, reason])
}
fn measured(right: &str, after: &str, target: &str, tol: &str, status: &str) -> String {
    row([
        &font_a(), "A", right, "extract_quadratic", &font_b(), "1000", after, target, "0.0", "700.0",
        "analytic_root_solve", "0.125", tol, "wall_tol", status, "",
    ])
}
/// Replaces one tab-separated field of a row by column index.
fn set(row: &str, index: usize, value: &str) -> String {
    let mut v: Vec<&str> = row.split('\t').collect();
    v[index] = value;
    v.join("\t")
}
fn run(rows: &[String]) -> Result<(usize, usize, usize), String> {
    run_with(rows, MANIFEST)
}
fn run_with(rows: &[String], manifest: &str) -> Result<(usize, usize, usize), String> {
    let m = parse_manifest(manifest)?;
    let mut t = COLUMNS.join("\t");
    t.push('\n');
    for r in rows {
        t.push_str(r);
        t.push('\n');
    }
    check_rows(&t, &m)
}

#[test]
fn committed_tables_are_well_formed() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/");
    let manifest = std::fs::read_to_string(format!("{dir}kern-verified-manifest.tsv")).expect("manifest");
    let rows = std::fs::read_to_string(format!("{dir}kern-verified-rows-schema.tsv")).expect("rows");
    check_rows(&rows, &parse_manifest(&manifest).unwrap()).unwrap();
}

#[test]
fn counts_and_the_tolerance_boundary() {
    assert_eq!(run(&[]), Ok((0, 0, 0)));
    let rows = [
        na_row("X", "missing_outline_evidence"),
        measured("Y", "10.0", "10.5", "0.5", "VERIFIED"),
        measured("Z", "10.0", "10.75", "0.5", "FAIL"),
    ];
    assert_eq!(run(&rows), Ok((1, 1, 1)));
    // The boundary is exact: a gap off by exactly tol is VERIFIED, and a one-digit excess is FAIL.
    assert_eq!(run(&[measured("Y", "0.3", "0.1", "0.2", "VERIFIED")]), Ok((1, 0, 0)));
    assert_eq!(run(&[measured("Y", "0.3", "0.1", "0.19999999999999999999", "FAIL")]), Ok((0, 1, 0)));
    assert!(run(&[measured("Y", "0.3", "0.1", "0.19999999999999999999", "VERIFIED")]).is_err());
}

#[test]
fn status_must_follow_the_measurement() {
    assert!(run(&[measured("Y", "10.0", "11.0", "0.5", "VERIFIED")]).is_err());
    assert!(run(&[measured("Y", "10.0", "10.1", "0.5", "FAIL")]).is_err());
}

#[test]
fn n_a_rows_are_typed_and_never_zero_or_pass() {
    assert!(run(&[na_row("Y", "pass")]).is_err());
    assert!(run(&[na_row("Y", "")]).is_err());
    assert!(run(&[set(&na_row("Y", "missing_outline_evidence"), 6, "0")]).is_err());
    assert!(run(&[na_row("Y", "no_vertical_overlap")]).is_err());
    let with_outline = |reason: &str| row([&font_a(), "A", "Y", "extract_cff", &font_b(), NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, reason]);
    assert!(run(&[with_outline("no_vertical_overlap")]).is_ok());
    assert!(run(&[with_outline("missing_outline_evidence")]).is_err());
    for why in ["tolerance_missing", "numerical_unresolved", "missing_wall_evidence"] {
        assert!(run(&[with_outline(why)]).is_ok(), "{why}");
        assert!(run(&[na_row("Y", why)]).is_ok(), "{why}");
    }
    assert!(run(&[row([&font_a(), "A", "Y", "extract_cff", NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, "missing_wall_evidence"])]).is_err());
}

fn vary(f: &dyn Fn(&mut Vec<String>)) -> String {
    let mut v: Vec<String> = measured("Y", "1.0", "1.0", "0.5", "VERIFIED").split('\t').map(String::from).collect();
    f(&mut v);
    v.join("\t")
}

#[test]
fn measured_rows_need_every_field() {
    assert!(run(&[vary(&|_| {})]).is_ok());
    assert!(run(&[vary(&|v| v[3] = NA.into())]).is_err());
    assert!(run(&[vary(&|v| v[4] = "x".into())]).is_err());
    assert!(run(&[vary(&|v| v[6] = "NaN".into())]).is_err());
    assert!(run(&[vary(&|v| v[7] = "inf".into())]).is_err());
    assert!(run(&[vary(&|v| v[8] = NA.into())]).is_err());
    assert!(run(&[vary(&|v| v[9] = NA.into())]).is_err());
    assert!(run(&[vary(&|v| v[12] = NA.into())]).is_err());
    assert!(run(&[vary(&|v| v[12] = "-0.5".into())]).is_err());
    assert!(run(&[vary(&|v| v[13] = "nope".into())]).is_err());
    assert!(run(&[vary(&|v| v[15] = "x".into())]).is_err());
    assert!(run(&[vary(&|v| v[14] = "pass".into())]).is_err());
}

#[test]
fn upm_is_a_positive_integer() {
    for bad in ["0", "-1", "+5", "1000.5", "abc", NA, "", " 5", "5 ", "\u{ff15}", "4294967296", "1e3"] {
        assert!(run(&[vary(&|v| v[5] = bad.into())]).is_err(), "{bad}");
    }
}

#[test]
fn error_bound_is_positive_covered_and_matches_the_manifest() {
    assert!(run(&[vary(&|v| v[11] = "0.0".into())]).is_err(), "zero is never assumed");
    assert!(run(&[vary(&|v| v[11] = "0.5".into())]).is_err(), "above the manifest bound");
    assert!(run(&[vary(&|v| v[12] = "0.1".into())]).is_err(), "tol below the error bound");
    assert!(run(&[vary(&|v| v[10] = "flatten".into())]).is_err(), "method differs from the manifest");
    assert!(run(&[vary(&|v| {
        v[8] = "9.0".into();
        v[9] = "1.0".into();
    })])
    .is_err());
    for column in [5, 6, 7, 8, 9, 10, 11, 12, 13] {
        assert!(run(&[set(&na_row("Y", "missing_outline_evidence"), column, "0")]).is_err(), "column {column}");
    }
}

#[test]
fn manifest_is_strict() {
    let tol = |extra: &str| format!("{MH}{extra}\n");
    let flat_method_alone = tol("tolerance\twall_tol\tCONVENTION\tfont_units\tflatten\t0.25\twritten derivation");
    assert!(run_with(&[measured("Y", "1.0", "1.0", "0.5", "VERIFIED")], &flat_method_alone).is_err());
    assert!(run_with(&[set(&measured("Y", "1.0", "1.0", "0.5", "VERIFIED"), 10, "flatten")], MANIFEST_FLAT).is_ok());
    for bad in [
        "tolerance\tx\tdefinition\tfont_units\tflatten\t1\td",
        "tolerance\tx\tCONVENTION\tpx\tflatten\t1\td",
        "tolerance\tx\tCONVENTION\tfont_units\tguess\t1\td",
        "tolerance\tx\tCONVENTION\tfont_units\tflatten\t0\td",
        "tolerance\tx\tCONVENTION\tfont_units\tflatten\tNaN\td",
        "tolerance\tx\tCONVENTION\tfont_units\tflatten\t1\t",
        "flatten\tx\tCONVENTION\tfont_units\tanalytic_root_solve\t1\td",
        "other\tx\tCONVENTION\tfont_units\tflatten\t1\td",
    ] {
        assert!(parse_manifest(&tol(bad)).is_err(), "{bad}");
    }
    assert!(parse_manifest("bad\n").is_err());
    let one = MANIFEST.lines().nth(1).unwrap();
    assert!(parse_manifest(&format!("{MANIFEST}{one}\n")).is_err());
}

#[test]
fn keys_and_shape_are_strict() {
    let a = na_row("Y", "missing_outline_evidence");
    assert!(run(&[a.clone(), a.clone()]).is_err());
    assert!(run(&[row(["A".repeat(SHA_HEX_LEN).as_str(), "A", "Y", NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, "missing_outline_evidence"])]).is_err());
    assert!(run(&[row([&font_a(), "", "Y", NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, "missing_outline_evidence"])]).is_err());
    assert!(run(&[format!("{a}\textra")]).is_err());
    assert!(check_rows("x\n", &parse_manifest(MANIFEST).unwrap()).is_err());
}

#[test]
fn decimal_grammar_is_one_plain_form() {
    for bad in ["1e3", "1E3", "+1", ".5", "1.", "-", "", "1_0", "\u{ff11}", "\u{0661}", " 1", "1 ", "1.2.3", "--1", "0x1", "NaN", "inf", "1,5"] {
        assert!(run(&[vary(&|v| v[6] = bad.into())]).is_err(), "{bad:?}");
        assert!(run(&[vary(&|v| v[12] = bad.into())]).is_err(), "{bad:?}");
    }
    for good in ["0", "-0", "7", "-7.25", "007.500", "123456.789"] {
        let same = |v: &mut Vec<String>| {
            v[6] = good.into();
            v[7] = good.into();
        };
        assert!(run(&[vary(&same)]).is_ok(), "{good}");
    }
    let flat = MANIFEST.replace("0.25", "1e-1");
    assert!(parse_manifest(&flat).is_err());
}

#[test]
fn overflow_is_a_typed_refusal_not_a_rounding() {
    let huge = "9".repeat(SHA_HEX_LEN);
    let e = run(&[vary(&|v| v[6] = huge.clone())]).unwrap_err();
    assert!(e.contains("overflow"), "{e}");
    let deep = format!("0.{}1", "0".repeat(SHA_HEX_LEN));
    let e = run(&[vary(&|v| v[7] = deep.clone())]).unwrap_err();
    assert!(e.contains("overflow"), "{e}");
}

#[test]
fn one_font_has_one_upm() {
    let y = measured("Y", "1.0", "1.0", "0.5", "VERIFIED");
    let z = set(&measured("Z", "1.0", "1.0", "0.5", "VERIFIED"), 5, "2048");
    assert!(run(&[y.clone(), z]).is_err());
    let other_font = set(&set(&measured("Y", "1.0", "1.0", "0.5", "VERIFIED"), 0, &font_b()), 5, "2048");
    assert!(run(&[y, other_font]).is_ok());
}

#[test]
fn rows_are_in_strict_byte_order() {
    let y = measured("Y", "1.0", "1.0", "0.5", "VERIFIED");
    let z = measured("Z", "1.0", "1.0", "0.5", "VERIFIED");
    assert!(run(&[y.clone(), z.clone()]).is_ok());
    assert!(run(&[z.clone(), y.clone()]).is_err());
    let left_b = set(&y, 1, "B");
    assert!(run(&[left_b.clone(), y.clone()]).is_err(), "left B sorts after A");
    assert!(run(&[y.clone(), left_b]).is_ok());
    let font_b_row = set(&y, 0, &font_b());
    assert!(run(&[font_b_row.clone(), y.clone()]).is_err());
    assert!(run(&[y, font_b_row]).is_ok());
}
