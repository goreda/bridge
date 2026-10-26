//! Before/after kern output on equal input.
//!
//! Input is a small synthetic fixture declared inline (test fixture, not font
//! data). The "before" snapshot is the proposal table produced by the commit
//! before the change; it is written once with
//!   cargo test --test kern_before_after -- --ignored write_snapshot
//! on that commit, and the file is committed with the test.
//!
//! Check: (0) a byte difference with no label row FAILS before any parsing;
//! (1) both tables pass the schema check (one #columns line, no blank line,
//! no duplicate pair, every row has exactly the declared field count, rows in
//! byte order of (left,right), one trailing newline); (2) the pair set is
//! equal and every changed field is
//! named in tests/fixtures/kern-snapshot-labels.tsv with a label
//! (columns: left, right, column, label; header lines use left="HEADER",
//! right="-", column="-"); (3) a label that matches no change is stale and
//! fails. With no labels the two tables must be byte-equal.

use kni_metrics::gen;
use kni_metrics::kern_proposal::build_proposal;
use std::collections::BTreeMap;

const CLASSES: &str = "\
A\tU\t0\t1\t1
B\tU\t0\t1\t1
C\tU\t0\t1\t1
a\tL\t0\t1\t1
b\tL\t0\t1\t1
c\tL\t0\t1\t1
";
const TARGETS: &str = "\
CELL\t1\t1\tLL\tn\t-23
CELL\t1\t1\tUU\tn\t-32
STRATUM\tn\tn\tLL\tn\t120
STRATUM\tn\tn\tUU\tn\t130
GLOBAL\tn\tn\tn\tn\t125
";
const EXISTING: &str = "\
a\tb\t-20
b\ta\t-24
a\ta\t-22
b\tb\t-26
A\tB\t-30
B\tA\t-34
A\tA\t-32
";

fn walls() -> String {
    // Declared synthetic walls: advance 600, rows y=0..4, left wall 50, right wall 550 (varying by glyph index).
    let mut s = String::new();
    for (i, g) in ["A", "B", "C", "a", "b", "c"].iter().enumerate() {
        for y in 0..5 {
            s.push_str(&format!("{}\t600\t{}\t{}\t{}\n", g, y, 50 + 4 * i, 550 - 3 * i));
        }
    }
    s
}

fn inputs() -> gen::GenerationInputs {
    let (glyphs, knowledge) = gen::parse_classes(CLASSES).unwrap();
    gen::GenerationInputs {
        glyphs,
        knowledge,
        targets: gen::parse_targets(TARGETS).unwrap(),
        walls: gen::parse_walls(&walls()).unwrap(),
        existing: gen::existing_from_pairs(gen::parse_pairs(EXISTING).unwrap()).unwrap(),
        restore: vec![],
    }
}

fn table() -> String {
    build_proposal(&inputs(), None).expect("proposal on the synthetic fixture").tsv()
}

fn fixture(name: &str) -> String {
    let p = format!("{}/tests/fixtures/{}", env!("CARGO_MANIFEST_DIR"), name);
    std::fs::read_to_string(&p).unwrap_or_else(|_| panic!("missing fixture {p}"))
}

#[test]
#[ignore = "run once on the BEFORE commit to write the snapshot"]
fn write_snapshot() {
    let p = format!("{}/tests/fixtures/kern-snapshot-before.tsv", env!("CARGO_MANIFEST_DIR"));
    std::fs::write(p, table()).unwrap();
}

struct Parsed {
    headers: Vec<String>,
    columns: Vec<String>,
    rows: BTreeMap<(String, String), Vec<String>>,
}

/// Minimum declared columns: the pair key is (left, right).
const MIN_COLUMNS: usize = 2;

/// Strict parse. Refuses what a lenient parse would hide: blank lines, a
/// missing or doubled #columns line, short or long rows, duplicate pairs,
/// rows out of (left,right) byte order, and a missing/extra trailing newline.
fn parse_strict(t: &str) -> Result<Parsed, String> {
    if !t.ends_with('\n') || t.ends_with("\n\n") {
        return Err("table must end with exactly one newline".into());
    }
    let mut p = Parsed { headers: vec![], columns: vec![], rows: BTreeMap::new() };
    let mut last: Option<(String, String)> = None;
    let mut have_columns = false;
    for (n, line) in t.lines().enumerate() {
        if line.is_empty() {
            return Err(format!("line {}: blank line", n + 1));
        }
        if line.split('\t').next() == Some("#columns") {
            if have_columns {
                return Err(format!("line {}: second #columns line", n + 1));
            }
            have_columns = true;
            p.columns = line.split('\t').skip(1).map(String::from).collect();
            if p.columns.len() < MIN_COLUMNS {
                return Err(format!("line {}: fewer than {} columns declared", n + 1, MIN_COLUMNS));
            }
            let uniq: std::collections::BTreeSet<&String> = p.columns.iter().collect();
            if uniq.len() != p.columns.len() || p.columns.iter().any(|c| c.is_empty()) {
                return Err(format!("line {}: column names must be unique and non-empty", n + 1));
            }
        } else if line.starts_with('#') {
            p.headers.push(line.to_string());
        } else {
            if !have_columns {
                return Err(format!("line {}: row before #columns", n + 1));
            }
            let f: Vec<String> = line.split('\t').map(String::from).collect();
            if f.len() != p.columns.len() {
                return Err(format!("line {}: {} fields, {} columns declared", n + 1, f.len(), p.columns.len()));
            }
            let key = (f[0].clone(), f[1].clone());
            if let Some(prev) = &last {
                if key <= *prev {
                    return Err(format!("line {}: row out of (left,right) byte order or duplicate", n + 1));
                }
            }
            last = Some(key.clone());
            if p.rows.insert(key, f).is_some() {
                return Err(format!("line {}: duplicate pair", n + 1));
            }
        }
    }
    if !have_columns {
        return Err("no #columns line".into());
    }
    Ok(p)
}

/// Labels: exactly four tab-separated, non-empty fields (left, right, column,
/// label); the (left, right, column) triple is unique. Anything else is a
/// schema refusal, never an index panic.
fn parse_labels(txt: &str) -> Result<Vec<Vec<String>>, String> {
    let mut out: Vec<Vec<String>> = vec![];
    let mut seen = std::collections::BTreeSet::new();
    for (n, l) in txt.lines().enumerate() {
        if l.starts_with('#') || l.trim().is_empty() {
            continue;
        }
        let f: Vec<String> = l.split('\t').map(String::from).collect();
        if f.len() != 4 {
            return Err(format!("line {}: expected 4 fields, found {}", n + 1, f.len()));
        }
        if f.iter().any(|x| x.trim().is_empty()) {
            return Err(format!("line {}: empty field", n + 1));
        }
        if !seen.insert((f[0].clone(), f[1].clone(), f[2].clone())) {
            return Err(format!("line {}: duplicate label for the same change", n + 1));
        }
        out.push(f);
    }
    Ok(out)
}

/// Pure comparison; returns the list of problems (empty = accepted).
fn compare(before: &str, after: &str, labels_txt: &str) -> Vec<String> {
    let labels = match parse_labels(labels_txt) {
        Ok(l) => l,
        Err(e) => return vec![format!("labels file: {e}")],
    };
    if before == after {
        return if labels.is_empty() { vec![] } else { vec!["labels present but output is byte-equal: stale labels".into()] };
    }
    // (0) byte difference needs labels, decided before any parsing.
    if labels.is_empty() {
        return vec!["bytes differ and no label row exists".into()];
    }
    let (b, a) = match (parse_strict(before), parse_strict(after)) {
        (Ok(b), Ok(a)) => (b, a),
        (Err(e), _) => return vec![format!("before table: {e}")],
        (_, Err(e)) => return vec![format!("after table: {e}")],
    };
    let mut bad: Vec<String> = vec![];
    if b.rows.keys().collect::<Vec<_>>() != a.rows.keys().collect::<Vec<_>>() {
        bad.push("PAIR SET differs between before and after".into());
        return bad;
    }
    let mut used: Vec<String> = vec![];
    let mut has = |l: &str, r: &str, c: &str| -> bool {
        for lab in &labels {
            if lab[0] == l && lab[1] == r && lab[2] == c {
                used.push(format!("{l}\t{r}\t{c}"));
                return true;
            }
        }
        false
    };
    if b.headers != a.headers && !has("HEADER", "-", "-") {
        bad.push("header lines changed without a label".into());
    }
    if b.columns != a.columns {
        bad.push("column set changed".into());
        return bad;
    }
    for (k, brow) in &b.rows {
        let arow = &a.rows[k];
        for (i, col) in a.columns.iter().enumerate() {
            if brow[i] != arow[i] && !has(&k.0, &k.1, col) {
                bad.push(format!("UNLABELED change {} {} column {}: {:?} -> {:?}", k.0, k.1, col, brow[i], arow[i]));
            }
        }
    }
    for lab in &labels {
        let key = format!("{}\t{}\t{}", lab[0], lab[1], lab[2]);
        if !used.contains(&key) {
            bad.push(format!("STALE label {key}"));
        }
    }
    bad
}

#[test]
fn equal_input_gives_equal_output_or_labeled_diff() {
    let before = fixture("kern-snapshot-before.tsv");
    let after = table();
    // The tables themselves must be well formed even when byte-equal.
    parse_strict(&before).expect("before snapshot is a well-formed table");
    parse_strict(&after).expect("after table is a well-formed table");
    let problems = compare(&before, &after, &fixture("kern-snapshot-labels.tsv"));
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn output_is_stable_across_runs() {
    assert_eq!(table(), table());
}

const T: &str = "#kern-proposal-table\tv1\n#columns\tleft\tright\tvalue\nA\tB\t-10\nA\tC\t-12\n";

#[test]
fn compare_self_check() {
    // equal, no labels: accepted
    assert!(compare(T, T, "").is_empty());
    // reorder only, zero labels: bytes differ => FAIL
    let reordered = "#kern-proposal-table\tv1\n#columns\tleft\tright\tvalue\nA\tC\t-12\nA\tB\t-10\n";
    assert!(!compare(T, reordered, "").is_empty());
    // trailing newline / blank line / duplicate / extra field, zero labels: FAIL
    assert!(!compare(T, &T.replace("-12\n", "-12\n\n"), "").is_empty());
    assert!(!compare(T, &T.trim_end().to_string(), "").is_empty());
    assert!(!compare(T, &T.replace("A\tC\t-12", "A\tB\t-12"), "").is_empty());
    assert!(!compare(T, &T.replace("A\tC\t-12", "A\tC\t-12\textra"), "").is_empty());
    // with a label the tables must still pass the schema check
    let lab = "A\tC\tvalue\tderivation changed\n";
    assert!(compare(T, &T.replace("-12", "-11"), lab).is_empty());
    assert!(!compare(T, &T.replace("A\tC\t-12", "A\tC\t-12\textra"), lab).is_empty());
    assert!(!compare(T, &T.replace("A\tC\t-12\n", "A\tC\t-12\n\n"), lab).is_empty());
    // reorder with an unrelated label: out-of-order row is refused by the strict parse
    assert!(!compare(T, reordered, lab).is_empty());
    // stale label on a table that did change another field
    assert!(!compare(T, &T.replace("-10", "-9"), lab).is_empty());
    // label present, output byte-equal: stale
    assert!(!compare(T, T, lab).is_empty());
    // duplicate pair with a label: strict parse refuses
    assert!(!compare(T, &T.replace("A\tC\t-12", "A\tB\t-12"), lab).is_empty());
    // pair set differs
    assert!(!compare(T, &T.replace("A\tC\t-12", "A\tD\t-12"), lab).is_empty());
}

#[test]
fn schema_refusals_are_typed_not_panics() {
    let lab = "A\tC\tvalue\tderivation changed\n";
    let changed = T.replace("-12", "-11");
    // #columns must be an exact token
    let junk = changed.replace("#columns\t", "#columnsJUNK\t");
    assert!(!compare(T, &junk, lab).is_empty());
    // short row: fewer fields than declared
    assert!(!compare(T, &changed.replace("A\tC\t-11", "A\tC"), lab).is_empty());
    // fewer than two columns declared
    let one = "#columns\tleft\nA\nB\n";
    assert!(!compare(T, one, lab).is_empty());
    // duplicate column names
    let dupcol = changed.replace("left\tright\tvalue", "left\tleft\tvalue");
    assert!(!compare(T, &dupcol, lab).is_empty());
    // labels: fewer than 4 fields, extra field, empty field, duplicate label
    for bad in ["A\tC\n", "A\tC\tvalue\n", "A\tC\tvalue\tx\textra\n", "A\tC\tvalue\t\n",
                "A\tC\tvalue\tx\nA\tC\tvalue\ty\n"] {
        let p = compare(T, &changed, bad);
        assert!(!p.is_empty() && p[0].starts_with("labels file"), "{bad:?}");
    }
    // a one-field label line must not panic the matcher
    assert!(!compare(T, &changed, "A\n").is_empty());
}

// ---------------------------------------------------------------------------
// Verified-row table type (kern-verified-rows.md, 16 columns, landed r6).
//
// Key = (font_sha256, left, right). The table must already pass the kern_verified_rows
// guard (shape, exact decimal grammar, status recomputed from the exact numbers, upm
// uniqueness); THIS comparison does not parse decimals and does not recompute status, it
// compares the two tables column by column as exact text. A byte difference with no
// label row fails before any parsing. Labels (TSV, five non-empty fields): font_sha256,
// left, right, column, label, where column is one of the 16 columns or the word ROW.
// ROW labels declare an added or dropped row; they are the only way a pair set may change,
// so an added or dropped row is always reported, never silent. A label that matches no
// change is stale and fails.

const VERIFIED_COLUMNS: [&str; 16] = [
    "font_sha256", "left", "right", "outline_source", "outline_sha256", "upm", "gap_after", "gap_target", "y_lo",
    "y_hi", "error_bound_method", "error_bound_value", "tol", "tolerance_label", "status", "reason",
];
const VERIFIED_NCOL: usize = VERIFIED_COLUMNS.len();
const VERIFIED_KEY_COLUMNS: usize = 3;
const VERIFIED_LABEL_FIELDS: usize = 5;
const ROW_LABEL_COLUMN: &str = "ROW";

type VerifiedKey = (String, String, String);

fn verified_parse(t: &str) -> Result<BTreeMap<VerifiedKey, Vec<String>>, String> {
    if !t.ends_with('\n') || t.ends_with("\n\n") {
        return Err("table must end with exactly one newline".into());
    }
    let mut lines = t.lines();
    let header: Vec<&str> = lines.next().map(|h| h.split('\t').collect()).unwrap_or_default();
    if header != VERIFIED_COLUMNS {
        return Err("header must be exactly the declared 16 columns".into());
    }
    let mut rows = BTreeMap::new();
    let mut last: Option<VerifiedKey> = None;
    for (i, line) in lines.enumerate() {
        let n = i + 2;
        if line.is_empty() {
            return Err(format!("line {n}: blank line"));
        }
        let f: Vec<String> = line.split('\t').map(String::from).collect();
        if f.len() != VERIFIED_NCOL {
            return Err(format!("line {n}: {} fields, {} columns declared", f.len(), VERIFIED_NCOL));
        }
        let key: VerifiedKey = (f[0].clone(), f[1].clone(), f[2].clone());
        if let Some(prev) = &last {
            if key <= *prev {
                return Err(format!("line {n}: row out of byte order or duplicate"));
            }
        }
        last = Some(key.clone());
        rows.insert(key, f);
    }
    Ok(rows)
}

fn verified_labels(txt: &str) -> Result<Vec<Vec<String>>, String> {
    let mut out: Vec<Vec<String>> = vec![];
    let mut seen = std::collections::BTreeSet::new();
    for (n, l) in txt.lines().enumerate() {
        if l.starts_with('#') || l.trim().is_empty() {
            continue;
        }
        let f: Vec<String> = l.split('\t').map(String::from).collect();
        if f.len() != VERIFIED_LABEL_FIELDS {
            return Err(format!("line {}: expected {} fields, found {}", n + 1, VERIFIED_LABEL_FIELDS, f.len()));
        }
        if f.iter().any(|x| x.trim().is_empty()) {
            return Err(format!("line {}: empty field", n + 1));
        }
        if f[VERIFIED_KEY_COLUMNS] != ROW_LABEL_COLUMN && !VERIFIED_COLUMNS.contains(&f[VERIFIED_KEY_COLUMNS].as_str()) {
            return Err(format!("line {}: unknown column {:?}", n + 1, f[VERIFIED_KEY_COLUMNS]));
        }
        if VERIFIED_COLUMNS[..VERIFIED_KEY_COLUMNS].contains(&f[VERIFIED_KEY_COLUMNS].as_str()) {
            return Err(format!("line {}: a key column cannot change; use ROW for added or dropped rows", n + 1));
        }
        let id = (f[0].clone(), f[1].clone(), f[2].clone(), f[3].clone());
        if !seen.insert(id) {
            return Err(format!("line {}: duplicate label for the same change", n + 1));
        }
        out.push(f);
    }
    Ok(out)
}

/// Pure comparison; returns the list of problems (empty = accepted).
fn compare_verified(before: &str, after: &str, labels_txt: &str) -> Vec<String> {
    let labels = match verified_labels(labels_txt) {
        Ok(l) => l,
        Err(e) => return vec![format!("labels file: {e}")],
    };
    if before == after {
        let own = verified_parse(before);
        return match (own, labels.is_empty()) {
            (Err(e), _) => vec![format!("table: {e}")],
            (Ok(_), true) => vec![],
            (Ok(_), false) => vec!["labels present but output is byte-equal: stale labels".into()],
        };
    }
    if labels.is_empty() {
        return vec!["bytes differ and no label row exists".into()];
    }
    let (b, a) = match (verified_parse(before), verified_parse(after)) {
        (Ok(b), Ok(a)) => (b, a),
        (Err(e), _) => return vec![format!("before table: {e}")],
        (_, Err(e)) => return vec![format!("after table: {e}")],
    };
    let mut used = std::collections::BTreeSet::new();
    let mut label_for = |k: &VerifiedKey, col: &str| -> bool {
        let hit = labels.iter().position(|l| l[0] == k.0 && l[1] == k.1 && l[2] == k.2 && l[VERIFIED_KEY_COLUMNS] == col);
        if let Some(i) = hit {
            used.insert(i);
        }
        hit.is_some()
    };
    let mut bad: Vec<String> = vec![];
    let keys: std::collections::BTreeSet<&VerifiedKey> = b.keys().chain(a.keys()).collect();
    for k in keys {
        match (b.get(k), a.get(k)) {
            (Some(br), Some(ar)) => {
                for (i, col) in VERIFIED_COLUMNS.iter().enumerate() {
                    if br[i] != ar[i] && !label_for(k, col) {
                        bad.push(format!("UNLABELED change {} {} {} column {}: {:?} -> {:?}", k.0, k.1, k.2, col, br[i], ar[i]));
                    }
                }
            }
            (Some(_), None) => {
                if !label_for(k, ROW_LABEL_COLUMN) {
                    bad.push(format!("UNLABELED dropped row {} {} {}", k.0, k.1, k.2));
                }
            }
            (None, Some(_)) => {
                if !label_for(k, ROW_LABEL_COLUMN) {
                    bad.push(format!("UNLABELED added row {} {} {}", k.0, k.1, k.2));
                }
            }
            (None, None) => unreachable!("key comes from one of the two tables"),
        }
    }
    for (i, l) in labels.iter().enumerate() {
        if !used.contains(&i) {
            bad.push(format!("STALE label {} {} {} {}", l[0], l[1], l[2], l[VERIFIED_KEY_COLUMNS]));
        }
    }
    bad
}

const TEST_FONT_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const TEST_FONT_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

fn vrow(font: &str, right: &str, after: &str, status: &str) -> String {
    format!(
        "{font}\tA\t{right}\textract_cff\t{font}\t1000\t{after}\t10\t0\t100\tanalytic_root_solve\t0.1\t0.5\twall_tol\t{status}\t\n"
    )
}

fn vtable(rows: &[String]) -> String {
    format!("{}\n{}", VERIFIED_COLUMNS.join("\t"), rows.concat())
}

#[test]
fn verified_rows_equal_input_equal_output() {
    let t = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED"), vrow(TEST_FONT_A, "C", "11", "VERIFIED")]);
    assert!(compare_verified(&t, &t, "").is_empty());
    // labels on equal tables are stale
    let lab = format!("{TEST_FONT_A}\tA\tC\tgap_after\tcalibrated\n");
    assert!(!compare_verified(&t, &t, &lab).is_empty());
}

#[test]
fn verified_field_change_needs_a_label() {
    let before = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED")]);
    let after = vtable(&[vrow(TEST_FONT_A, "B", "12", "FAIL")]);
    assert!(!compare_verified(&before, &after, "").is_empty());
    // both changed columns must be labelled, one label alone leaves an unlabelled change
    let one = format!("{TEST_FONT_A}\tA\tB\tgap_after\tremeasured\n");
    let p = compare_verified(&before, &after, &one);
    assert!(p.iter().any(|x| x.contains("UNLABELED") && x.contains("status")), "{p:?}");
    let both = format!("{one}{TEST_FONT_A}\tA\tB\tstatus\tfollows gap_after\n");
    assert!(compare_verified(&before, &after, &both).is_empty());
}

#[test]
fn verified_added_or_dropped_row_is_reported() {
    let two = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED"), vrow(TEST_FONT_B, "B", "10", "VERIFIED")]);
    let one = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED")]);
    let p = compare_verified(&two, &one, &format!("{TEST_FONT_A}\tA\tB\tgap_after\tx\n"));
    assert!(p.iter().any(|x| x.contains("UNLABELED dropped row")), "{p:?}");
    assert!(p.iter().any(|x| x.contains("STALE")), "{p:?}");
    let drop_label = format!("{TEST_FONT_B}\tA\tB\tROW\tfont removed from the sweep\n");
    assert!(compare_verified(&two, &one, &drop_label).is_empty());
    let p = compare_verified(&one, &two, "");
    assert!(!p.is_empty());
    assert!(compare_verified(&one, &two, &drop_label).is_empty());
    // the same label cannot stand for a change in a key column
    let key_label = format!("{TEST_FONT_B}\tA\tB\tleft\tx\n");
    assert!(compare_verified(&two, &one, &key_label)[0].starts_with("labels file"));
}

#[test]
fn verified_schema_refusals_are_typed_not_panics() {
    let good = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED")]);
    let changed = vtable(&[vrow(TEST_FONT_A, "B", "12", "VERIFIED")]);
    let lab = format!("{TEST_FONT_A}\tA\tB\tgap_after\tx\n");
    assert!(compare_verified(&good, &changed, &lab).is_empty());
    // wrong header, missing newline, blank line, short row, out of order, duplicate
    assert!(!compare_verified(&good, &changed.replace("outline_source", "outline_src"), &lab).is_empty());
    assert!(!compare_verified(&good, changed.trim_end(), &lab).is_empty());
    assert!(!compare_verified(&good, &format!("{changed}\n"), &lab).is_empty());
    assert!(!compare_verified(&good, &changed.replace("\textract_cff", ""), &lab).is_empty());
    let unordered = vtable(&[vrow(TEST_FONT_B, "B", "10", "VERIFIED"), vrow(TEST_FONT_A, "B", "10", "VERIFIED")]);
    assert!(!compare_verified(&good, &unordered, &lab).is_empty());
    let dup = vtable(&[vrow(TEST_FONT_A, "B", "10", "VERIFIED"), vrow(TEST_FONT_A, "B", "10", "VERIFIED")]);
    assert!(!compare_verified(&good, &dup, &lab).is_empty());
    // labels: short, extra, empty, unknown column, duplicate
    let bad_labels: Vec<String> = vec![
        "a\tA\tB\n".to_string(),
        format!("{TEST_FONT_A}\tA\tB\tgap_after\tx\textra\n"),
        format!("{TEST_FONT_A}\tA\tB\tgap_after\t\n"),
        format!("{TEST_FONT_A}\tA\tB\tnot_a_column\tx\n"),
        format!("{TEST_FONT_A}\tA\tB\tgap_after\tx\n{TEST_FONT_A}\tA\tB\tgap_after\ty\n"),
    ];
    for bad in &bad_labels {
        let p = compare_verified(&good, &changed, bad);
        assert!(!p.is_empty() && p[0].starts_with("labels file"), "{bad:?}");
    }
    // an equal but malformed table is still refused
    assert!(!compare_verified(&good.trim_end().to_string(), &good.trim_end().to_string(), "").is_empty());
}

#[test]
fn verified_n_a_row_change_is_an_ordinary_labelled_change() {
    let na = format!(
        "{TEST_FONT_A}\tA\tB\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tn/a\tmissing_wall_evidence\n"
    );
    let na2 = na.replace("missing_wall_evidence", "no_vertical_overlap");
    let lab = format!("{TEST_FONT_A}\tA\tB\treason\tthe wall result now reports an open band\n");
    assert!(compare_verified(&vtable(&[na.clone()]), &vtable(&[na2.clone()]), &lab).is_empty());
    assert!(!compare_verified(&vtable(&[na]), &vtable(&[na2]), "").is_empty());
}
