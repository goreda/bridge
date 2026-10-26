//! Kern-engine numeric literal guard. TOKEN SCAN, not an AST check.
//!
//! Rule: every numeric literal in the scoped source files is either a trivial
//! literal (TRIVIAL below) or is listed in tests/fixtures/kern-scope-literals.tsv
//! with an exact per-file count, a class and a written note. A new literal,
//! a removed literal (stale row), or a new source file that is not in the
//! scope list fails the test.
//!
//! Scanner behaviour (explicit):
//! - comments, string/char/byte/raw-string contents are not scanned;
//! - items following `#[cfg(test)]` (a braced block or a `;` item) are exempt;
//! - literals inside macro bodies, array lengths and range bounds ARE scanned;
//! - tuple-field indices (`x.0`) are not counted;
//! - KNOWN GAPS: numbers inside format strings (e.g. precision in "{:.3}")
//!   and numbers inside string tables are invisible to this guard; string
//!   based rules must be inventoried separately.

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

/// Literals accepted anywhere without a row. Declared here on purpose.
const TRIVIAL: [&str; 4] = ["0", "1", "0.0", "1.0"];

const CLASSES: [&str; 10] = [
    "derived", "convention", "definition", "format", "report", "dead-code",
    "allowlist-fips", "removed-candidate", "open", "pending",
];
/// Classes that the closure test (ignored by default) refuses.
const PENDING_CLASSES: [&str; 3] = ["pending", "open", "removed-candidate"];

const SUFFIXES: [&str; 14] = [
    "usize", "isize", "u128", "i128", "u64", "i64", "u32", "i32", "u16", "i16", "u8", "i8",
    "f64", "f32",
];

fn is_ident_char(c: char) -> bool {
    c.is_alphanumeric() || c == '_'
}

pub fn normalize(tok: &str) -> String {
    let mut t: String = tok.chars().filter(|c| *c != '_').collect::<String>().to_lowercase();
    let hex = t.starts_with("0x") || t.starts_with("0b") || t.starts_with("0o");
    for s in SUFFIXES.iter() {
        if hex && (*s == "f32" || *s == "f64") {
            continue;
        }
        if t.len() > s.len() && t.ends_with(s) {
            let cut = t.len() - s.len();
            t.truncate(cut);
            break;
        }
    }
    t
}

/// Returns the normalized numeric literal tokens of `src` outside comments,
/// strings and `#[cfg(test)]` items (trivial literals NOT yet removed).
pub fn scan_literals(src: &str) -> Vec<String> {
    let b: Vec<char> = src.chars().collect();
    let n = b.len();
    let mut i = 0usize;
    let mut out: Vec<String> = Vec::new();
    let mut pending_test = false;
    let mut test_depth: i64 = 0;
    let cfg_test: Vec<char> = "#[cfg(test)]".chars().collect();
    while i < n {
        let c = b[i];
        let nx = if i + 1 < n { b[i + 1] } else { '\0' };
        if c == '/' && nx == '/' {
            while i < n && b[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '/' && nx == '*' {
            let mut depth = 1;
            i += 2;
            while i < n && depth > 0 {
                if b[i] == '/' && i + 1 < n && b[i + 1] == '*' {
                    depth += 1;
                    i += 2;
                } else if b[i] == '*' && i + 1 < n && b[i + 1] == '/' {
                    depth -= 1;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            continue;
        }
        let prev_ident = i > 0 && is_ident_char(b[i - 1]);
        // raw strings: r"..", r#".."#, br".."
        if !prev_ident && (c == 'r' || (c == 'b' && nx == 'r')) {
            let mut j = i + if c == 'b' { 2 } else { 1 };
            let mut hashes = 0usize;
            while j < n && b[j] == '#' {
                hashes += 1;
                j += 1;
            }
            if j < n && b[j] == '"' {
                j += 1;
                loop {
                    if j >= n {
                        break;
                    }
                    if b[j] == '"' {
                        let mut k = 0;
                        while k < hashes && j + 1 + k < n && b[j + 1 + k] == '#' {
                            k += 1;
                        }
                        if k == hashes {
                            j += 1 + hashes;
                            break;
                        }
                    }
                    j += 1;
                }
                i = j;
                continue;
            }
        }
        if c == '"' || (!prev_ident && c == 'b' && nx == '"') {
            i += if c == 'b' { 2 } else { 1 };
            while i < n && b[i] != '"' {
                i += if b[i] == '\\' { 2 } else { 1 };
            }
            i += 1;
            continue;
        }
        if c == '\'' || (!prev_ident && c == 'b' && nx == '\'') {
            let s = if c == 'b' { i + 1 } else { i };
            if s + 1 < n && b[s + 1] == '\\' {
                let mut j = s + 2;
                while j < n && b[j] != '\'' {
                    j += 1;
                }
                i = j + 1;
                continue;
            }
            if s + 2 < n && b[s + 2] == '\'' {
                i = s + 3;
                continue;
            }
            i = s + 1; // lifetime or label
            continue;
        }
        if c == '#' && i + cfg_test.len() <= n && b[i..i + cfg_test.len()] == cfg_test[..] {
            pending_test = true;
            i += cfg_test.len();
            continue;
        }
        if c == '{' {
            if pending_test {
                pending_test = false;
                test_depth = 1;
            } else if test_depth > 0 {
                test_depth += 1;
            }
            i += 1;
            continue;
        }
        if c == '}' {
            if test_depth > 0 {
                test_depth -= 1;
            }
            i += 1;
            continue;
        }
        if c == ';' && pending_test {
            pending_test = false;
            i += 1;
            continue;
        }
        if c.is_alphabetic() || c == '_' {
            while i < n && is_ident_char(b[i]) {
                i += 1;
            }
            continue;
        }
        if c.is_ascii_digit() {
            let start = i;
            let radix_prefix = c == '0' && (nx == 'x' || nx == 'b' || nx == 'o');
            if radix_prefix {
                i += 2;
                while i < n && is_ident_char(b[i]) {
                    i += 1;
                }
            } else {
                while i < n && (b[i].is_ascii_digit() || b[i] == '_') {
                    i += 1;
                }
                if i + 1 < n && b[i] == '.' && b[i + 1].is_ascii_digit() {
                    i += 1;
                    while i < n && (b[i].is_ascii_digit() || b[i] == '_') {
                        i += 1;
                    }
                }
                if i < n && (b[i] == 'e' || b[i] == 'E') {
                    let a = if i + 1 < n { b[i + 1] } else { '\0' };
                    let a2 = if i + 2 < n { b[i + 2] } else { '\0' };
                    if a.is_ascii_digit() || ((a == '+' || a == '-') && a2.is_ascii_digit()) {
                        i += 2;
                        while i < n && (b[i].is_ascii_digit() || b[i] == '_') {
                            i += 1;
                        }
                    }
                }
                while i < n && is_ident_char(b[i]) {
                    i += 1;
                }
            }
            let tuple_index = start > 0 && b[start - 1] == '.' && !(start > 1 && b[start - 2] == '.');
            if !tuple_index && test_depth == 0 && !pending_test {
                let tok: String = b[start..i].iter().collect();
                out.push(normalize(&tok));
            }
            continue;
        }
        i += 1;
    }
    out
}

pub fn counted(src: &str) -> BTreeMap<String, usize> {
    let mut m = BTreeMap::new();
    for l in scan_literals(src) {
        if TRIVIAL.contains(&l.as_str()) {
            continue;
        }
        *m.entry(l).or_insert(0) += 1;
    }
    m
}

struct Fixture {
    scope: Vec<String>,
    rows: BTreeMap<(String, String), (usize, String, String)>, // (file,lit)->(count,class,note)
}

fn manifest() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn load_fixture() -> Fixture {
    let p = manifest().join("tests/fixtures/kern-scope-literals.tsv");
    let text = fs::read_to_string(&p).expect("fixture kern-scope-literals.tsv must exist");
    let mut f = Fixture { scope: vec![], rows: BTreeMap::new() };
    for (ln, line) in text.lines().enumerate() {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let c: Vec<&str> = line.split('\t').collect();
        match c[0] {
            "scope" => {
                assert!(c.len() >= 2, "line {}: scope needs a path", ln + 1);
                f.scope.push(c[1].to_string());
            }
            "lit" => {
                assert!(c.len() >= 6, "line {}: lit needs file,literal,count,class,note", ln + 1);
                let cnt: usize = c[3].parse().expect("count");
                let prev = f.rows.insert((c[1].into(), c[2].into()), (cnt, c[4].into(), c[5].into()));
                assert!(prev.is_none(), "line {}: duplicate row", ln + 1);
            }
            other => panic!("line {}: unknown row kind {}", ln + 1, other),
        }
    }
    f
}

fn engine_root() -> PathBuf {
    manifest().join("..")
}

fn discover() -> Vec<String> {
    let mut v = vec![];
    for dir in ["metrics/src", "learning/src"] {
        for e in fs::read_dir(engine_root().join(dir)).expect("source dir") {
            let p = e.unwrap().path();
            if p.extension().map_or(false, |x| x == "rs") {
                v.push(format!("{}/{}", dir, p.file_name().unwrap().to_string_lossy()));
            }
        }
    }
    v.sort();
    v
}

#[test]
fn scope_is_exactly_the_listed_files() {
    let fx = load_fixture();
    let mut listed = fx.scope.clone();
    listed.sort();
    assert_eq!(discover(), listed, "a source file entered or left the kern scope without a scope row");
}

#[test]
fn literals_match_the_fixture_exactly() {
    let fx = load_fixture();
    let mut problems = vec![];
    let mut seen = std::collections::BTreeSet::new();
    for file in &fx.scope {
        let src = fs::read_to_string(engine_root().join(file)).expect("scoped file");
        for (lit, cnt) in counted(&src) {
            match fx.rows.get(&(file.clone(), lit.clone())) {
                None => problems.push(format!("NEW literal {} x{} in {}", lit, cnt, file)),
                Some((c, _, _)) if *c != cnt => {
                    problems.push(format!("COUNT {} in {}: fixture {} found {}", lit, file, c, cnt))
                }
                _ => {
                    seen.insert((file.clone(), lit));
                }
            }
        }
    }
    for k in fx.rows.keys() {
        if !seen.contains(k) {
            problems.push(format!("STALE row {} in {}", k.1, k.0));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

/// `format` -> [(format, count)]; `definition:11,format:2` -> parts.
/// None when the parts do not add up to the count.
fn split_classes(class: &str, count: usize) -> Option<Vec<(String, usize)>> {
    if !class.contains(':') {
        return Some(vec![(class.to_string(), count)]);
    }
    let mut out = vec![];
    for part in class.split(',') {
        let mut it = part.splitn(2, ':');
        let name = it.next()?.to_string();
        let n: usize = it.next()?.parse().ok()?;
        out.push((name, n));
    }
    if out.iter().map(|(_, n)| *n).sum::<usize>() == count { Some(out) } else { None }
}

#[test]
fn split_classes_sum_to_counts_and_justifications_nonempty() {
    let fx = load_fixture();
    for ((file, lit), (count, class, note)) in &fx.rows {
        if class.contains(':') {
            let parts = split_classes(class, *count).unwrap_or_else(|| {
                panic!("{} {}: class split {} does not add up to count {}", file, lit, class, count)
            });
            let sum: usize = parts.iter().map(|(_, n)| *n).sum();
            assert_eq!(sum, *count, "{} {}: class split {} sums to {}, count {}", file, lit, class, sum, count);
        } else {
            assert!(!note.trim().is_empty(), "{} {}: unsplit class {} needs a nonempty justification", file, lit, class);
        }
    }
}

#[test]
fn fixture_rows_are_complete() {
    let fx = load_fixture();
    for ((file, lit), (count, class, note)) in &fx.rows {
        let parts = split_classes(class, *count)
            .unwrap_or_else(|| panic!("{} {}: class split {} does not add up to count {}", file, lit, class, count));
        for (name, _) in &parts {
            assert!(CLASSES.contains(&name.as_str()), "{} {}: unknown class {}", file, lit, name);
        }
        assert!(!note.trim().is_empty(), "{} {}: note (derivation / reason / spec reference) is empty", file, lit);
        assert!(fx.scope.contains(file), "{}: row for a file outside scope", file);
    }
}

#[test]
fn scanner_self_check() {
    let src = r##"
        // 7 in a comment
        /* 8 /* nested 9 */ 10 */
        const A: u8 = 1_000; const B: u32 = 0x1F; const C: f64 = 1e-12; const D: u8 = 2u8;
        const E: f64 = 2.5e3_f64; static F: [u8; 16] = [0u8; 16];
        fn f<'a>(x: &'a str) { let c = '5'; let d = '\n'; let s = "99 {:.3}"; let r = r#"77"#; let t = x.0; }
        macro_rules! m { () => { 33 }; }
        fn g() { for i in 0..10 {} let _ = 4..=6; }
        #[cfg(test)]
        mod tests { const T: i32 = 555; mod inner { const U: i32 = 556; } }
        const AFTER: i32 = 42;
        const Z: f64 = 1.0; const O: i32 = 0;
    "##;
    let m = counted(src);
    let mut got: Vec<(String, usize)> = m.into_iter().collect();
    got.sort();
    let mut want: Vec<(String, usize)> = vec![
        ("1000", 1), ("0x1f", 1), ("1e-12", 1), ("2", 1), ("2.5e3", 1), ("16", 2),
        ("33", 1), ("10", 1), ("4", 1), ("6", 1), ("42", 1),
    ].into_iter().map(|(a, b)| (a.to_string(), b)).collect();
    want.sort();
    assert_eq!(got, want);
}

/// Closure gate: fails while any row is pending, open or a removal candidate.
/// Run with `cargo test -- --ignored` for the closure receipt.
#[test]
#[ignore = "closure gate: rows still pending/open"]
fn closure_no_pending_rows() {
    let fx = load_fixture();
    let pend: Vec<String> = fx.rows.iter()
        .filter(|(_, (n, c, _))| {
            split_classes(c, *n).map_or(true, |ps| ps.iter().any(|(k, _)| PENDING_CLASSES.contains(&k.as_str())))
        })
        .map(|((f, l), (n, c, _))| format!("{} {} x{} [{}]", f, l, n, c))
        .collect();
    assert!(pend.is_empty(), "{} pending rows:\n{}", pend.len(), pend.join("\n"));
}

/// Receipt: literal count per class. Run with `--nocapture`.
#[test]
fn receipt_counts_per_class() {
    let fx = load_fixture();
    let mut per: BTreeMap<String, usize> = BTreeMap::new();
    for (_, (cnt, class, _)) in &fx.rows {
        for (name, n) in split_classes(class, *cnt).unwrap_or_default() {
            *per.entry(name).or_insert(0) += n;
        }
    }
    println!("RECEIPT literals-per-class {:?} (token scan, not AST; tree sha and fixture sha are recorded outside this test)", per);
}
