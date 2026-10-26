//! Guard: a new bare numeric literal in the kern path fails this test.
//!
//! The pinned list is `tests/fixtures/kern-literals.tsv`. Each literal of the
//! guarded files (test modules excluded) must be listed with a class:
//! structural (any count: counting, indexing, median arithmetic), format
//! (pinned count), definition (pinned count), CONVENTION or derived (pinned
//! count, with a note). A literal not in the list, or a count that differs, is
//! a failure. To add a number, give it a class and a derivation in the list and
//! in the constants inventory.

use std::collections::BTreeMap;

/// Same rules as the scan that produced the pinned list: drop the test module,
/// comments, string and char literals; read numeric literals; skip tuple
/// field indexes such as `a.0`.
fn strip(src: &str) -> Vec<char> {
    let src = match src.find("#[cfg(test)]") {
        Some(i) => &src[..i],
        None => src,
    };
    let s: Vec<char> = src.chars().collect();
    let n = s.len();
    let mut out = Vec::with_capacity(n);
    let mut k = 0;
    while k < n {
        let c = s[k];
        if c == '/' && k + 1 < n && s[k + 1] == '/' {
            while k < n && s[k] != '\n' {
                k += 1;
            }
        } else if c == '/' && k + 1 < n && s[k + 1] == '*' {
            k += 2;
            while k + 1 < n && !(s[k] == '*' && s[k + 1] == '/') {
                k += 1;
            }
            k = (k + 2).min(n);
        } else if c == '"' {
            k += 1;
            while k < n && s[k] != '"' {
                k += if s[k] == '\\' { 2 } else { 1 };
            }
            k += 1;
            out.push(' ');
        } else if c == '\'' && k + 2 < n && (s[k + 2] == '\'' || s[k + 1] == '\\') {
            k += 1;
            while k < n && s[k] != '\'' {
                k += if s[k] == '\\' { 2 } else { 1 };
            }
            k += 1;
            out.push(' ');
        } else {
            out.push(c);
            k += 1;
        }
    }
    out
}

fn literals(src: &str) -> BTreeMap<String, usize> {
    let s = strip(src);
    let n = s.len();
    let mut found: BTreeMap<String, usize> = BTreeMap::new();
    let word = |c: char| c.is_alphanumeric() || c == '_';
    let mut k = 0;
    while k < n {
        let c = s[k];
        if c.is_ascii_digit() && (k == 0 || !word(s[k - 1])) {
            let prev = if k > 0 { s[k - 1] } else { ' ' };
            let mut j = k;
            let radix = k + 1 < n && s[k] == '0' && matches!(s[k + 1], 'x' | 'b' | 'o');
            if radix {
                j = k + 2;
                while j < n && word(s[j]) {
                    j += 1;
                }
            } else {
                while j < n && (s[j].is_ascii_digit() || s[j] == '_') {
                    j += 1;
                }
                if j + 1 < n && s[j] == '.' && s[j + 1].is_ascii_digit() {
                    j += 1;
                    while j < n && (s[j].is_ascii_digit() || s[j] == '_') {
                        j += 1;
                    }
                }
                if j + 1 < n
                    && matches!(s[j], 'e' | 'E')
                    && (s[j + 1].is_ascii_digit()
                        || (matches!(s[j + 1], '+' | '-') && j + 2 < n && s[j + 2].is_ascii_digit()))
                {
                    j += 2;
                    while j < n && s[j].is_ascii_digit() {
                        j += 1;
                    }
                }
                while j < n && word(s[j]) {
                    j += 1;
                }
            }
            if !(prev == '.' && !(k >= 2 && s[k - 2] == '.')) {
                *found.entry(s[k..j].iter().collect()).or_insert(0) += 1;
            }
            k = j;
        } else if c.is_alphabetic() || c == '_' {
            while k < n && word(s[k]) {
                k += 1;
            }
        } else {
            k += 1;
        }
    }
    found
}

#[test]
fn kern_path_has_no_unlisted_numeric_literal() {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let root = manifest.parent().and_then(|p| p.parent()).expect("repository root");
    let list = std::fs::read_to_string(manifest.join("tests/fixtures/kern-literals.tsv")).expect("pinned list");

    // file -> literal -> (count or None for any, class, note)
    let mut pinned: BTreeMap<String, BTreeMap<String, (Option<usize>, String, String)>> = BTreeMap::new();
    for (i, line) in list.lines().enumerate().skip(1) {
        if line.trim().is_empty() {
            continue;
        }
        let f: Vec<&str> = line.split('\t').collect();
        assert_eq!(f.len(), 5, "pinned list line {} has {} columns", i + 1, f.len());
        let class = f[3];
        assert!(
            ["structural", "format", "definition", "CONVENTION", "derived"].contains(&class),
            "pinned list line {}: unknown class {class}",
            i + 1
        );
        let count = if f[2] == "*" { None } else { Some(f[2].parse::<usize>().expect("count")) };
        assert!(count.is_none() == (class == "structural"), "line {}: only structural literals take any count", i + 1);
        assert!(!f[4].trim().is_empty(), "line {}: every entry carries a note", i + 1);
        pinned
            .entry(f[0].to_string())
            .or_default()
            .insert(f[1].to_string(), (count, class.to_string(), f[4].to_string()));
    }
    assert!(!pinned.is_empty());

    let mut problems: Vec<String> = Vec::new();
    for (rel, lits) in &pinned {
        let text = std::fs::read_to_string(root.join(rel)).unwrap_or_else(|e| panic!("{rel}: {e}"));
        let found = literals(&text);
        for (lit, n) in &found {
            match lits.get(lit) {
                None => problems.push(format!("{rel}: unlisted numeric literal {lit} (x{n})")),
                Some((Some(want), _, _)) if want != n => {
                    problems.push(format!("{rel}: literal {lit} appears {n} times, pinned {want}"))
                }
                _ => {}
            }
        }
        for (lit, (count, _, _)) in lits {
            if count.is_some() && !found.contains_key(lit) {
                problems.push(format!("{rel}: pinned literal {lit} no longer appears; update the list"));
            }
        }
    }
    assert!(problems.is_empty(), "kern constants guard:\n{}", problems.join("\n"));
}

#[test]
fn scanner_reads_literals_the_way_the_pinned_list_was_made() {
    let src = "fn f(a: (i32, i32)) -> f64 {\n    // 99 in a comment\n    let s = \"77\"; let c = '5';\n    let x = a.0 + 3 + 0usize as i32; let y = 2.5e-3 + 1.0;\n    for i in 0..4 { let _ = i; }\n    let z7 = 8; x as f64 + y\n}\n#[cfg(test)]\nmod t { fn g() { let _ = 123; } }\n";
    let l = literals(src);
    let keys: Vec<&str> = l.keys().map(|s| s.as_str()).collect();
    assert_eq!(keys, vec!["0", "0usize", "1.0", "2.5e-3", "3", "4", "8"]);
}
