//! k6_provenance.rs — K6: every artifact carries a provenance block.
//!
//! Second-half deliverable, add-only, fix-forward v2.
//! Base: snapshots/261018-2214-integrated-tip. English-only (item 14).
//!
//! Finding B24-06: "which code produced this otf" had no answer. From here,
//! any artifact emitted through this wire answers: which code, which
//! commit, when (utc), which inputs (plural), and what artifact came out
//! {name, sha256, bytes} — the task schema (review item 13).
//!
//! Normalization rules (F9/F10/item 13): hex values are stored
//! lowercase — the same hash can never produce two different JSONs; code_id
//! and commit are stored TRIMMED (validation without storage-normalization
//! let " k1-wire/1 " leak into JSON); reserved keys cannot enter `extra`,
//! so duplicate JSON keys are impossible by construction.
//!
//! Std-only; serialization is manual JSON with a real escaper (item 12):
//! Debug formatting is not JSON.

use std::collections::BTreeMap;
use std::fmt::Write as _;

/// Reserved top-level keys: `extra` may never shadow them (F10).
const RESERVED_KEYS: [&str; 6] = ["code_id", "commit", "utc", "artifact", "inputs", "extra"];

#[derive(Debug, Clone, PartialEq)]
pub struct Artifact {
    pub name: String,
    pub sha256: String, // 64 hex, lowercase-normalized
    pub bytes: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Provenance {
    pub code_id: String,  // trimmed at construction
    pub commit: String,   // exactly 40 hex, lowercase-normalized (G-e)
    pub utc: String,      // ISO-8601 UTC: YYYY-MM-DDTHH:MM:SSZ
    pub artifact: Artifact,
    pub inputs: Vec<String>, // plural input hashes, 64 hex, lowercase-normalized
    extra: BTreeMap<String, String>, // private: reserved keys cannot enter (F10)
}

fn normalize_hex(value: &str, want_len: usize, what: &str) -> Result<String, String> {
    let v = value.trim().to_ascii_lowercase();
    if v.len() != want_len || !v.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!(
            "K6: {} must be {} hex chars (normalized lowercase) — refused",
            what, want_len
        ));
    }
    Ok(v)
}

fn valid_utc(s: &str) -> bool {
    // Shape: YYYY-MM-DDTHH:MM:SSZ with sane field ranges.
    let b = s.as_bytes();
    if b.len() != 20 || b[4] != b'-' || b[7] != b'-' || b[10] != b'T'
        || b[13] != b':' || b[16] != b':' || b[19] != b'Z' {
        return false;
    }
    let num = |from: usize, to: usize| -> Option<u32> {
        s[from..to].parse().ok()
    };
    match (num(0, 4), num(5, 7), num(8, 10), num(11, 13), num(14, 16), num(17, 19)) {
        (Some(_y), Some(mo), Some(d), Some(h), Some(mi), Some(se)) => {
            (1..=12).contains(&mo) && (1..=31).contains(&d)
                && h <= 23 && mi <= 59 && se <= 60
        }
        _ => false,
    }
}

/// Real JSON string escaping (item 12): control characters become \u00XX,
/// never Rust-style \u{XX} or raw bytes.
pub fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                write!(out, "\\u{:04x}", c as u32).unwrap();
            }
            c => out.push(c),
        }
    }
    out
}

impl Provenance {
    pub fn new(
        code_id: &str,
        commit: &str,
        utc: &str,
        artifact: Artifact,
        inputs: Vec<String>,
    ) -> Result<Self, String> {
        let code_id = code_id.trim();
        if code_id.is_empty() {
            return Err("K6: provenance without code id — refused".into());
        }
        // G-e: commit is exactly 40 hex ("HEAD"/"unknown" cannot pass).
        let commit = normalize_hex(commit, 40, "commit")?;
        if !valid_utc(utc) {
            return Err(format!("K6: utc {:?} is not YYYY-MM-DDTHH:MM:SSZ — refused", utc));
        }
        let artifact_name = artifact.name.trim();
        if artifact_name.is_empty() {
            return Err("K6: artifact without name — refused".into());
        }
        let artifact = Artifact {
            name: artifact_name.to_string(),
            sha256: normalize_hex(&artifact.sha256, 64, "artifact sha256")?,
            bytes: artifact.bytes,
        };
        if inputs.is_empty() {
            return Err("K6: provenance without any input hash — refused".into());
        }
        let inputs = inputs
            .iter()
            .map(|h| normalize_hex(h, 64, "input hash"))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Provenance {
            code_id: code_id.to_string(),
            commit,
            utc: utc.to_string(),
            artifact,
            inputs,
            extra: BTreeMap::new(),
        })
    }

    /// The only way in for extra keys: reserved keys and empty keys are
    /// refused, so duplicate JSON keys are impossible by construction (F10).
    pub fn insert_extra(&mut self, key: &str, value: &str) -> Result<(), String> {
        let key = key.trim();
        if key.is_empty() {
            return Err("K6: empty extra key — refused".into());
        }
        if RESERVED_KEYS.contains(&key) {
            return Err(format!("K6: extra key {:?} is reserved — refused", key));
        }
        self.extra.insert(key.to_string(), value.to_string());
        Ok(())
    }

    pub fn extra(&self) -> &BTreeMap<String, String> {
        &self.extra
    }

    /// Deterministic JSON (sorted extra keys): equal provenance, equal JSON.
    pub fn to_json(&self) -> String {
        let mut s = String::from("{");
        write!(
            s,
            "\"artifact\":{{\"bytes\":{},\"name\":\"{}\",\"sha256\":\"{}\"}},",
            self.artifact.bytes,
            json_escape(&self.artifact.name),
            self.artifact.sha256
        )
        .unwrap();
        write!(s, "\"code_id\":\"{}\",", json_escape(&self.code_id)).unwrap();
        write!(s, "\"commit\":\"{}\",", self.commit).unwrap();
        s.push_str("\"inputs\":[");
        for (i, h) in self.inputs.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            write!(s, "\"{}\"", h).unwrap();
        }
        s.push_str("],");
        write!(s, "\"utc\":\"{}\"", json_escape(&self.utc)).unwrap();
        if !self.extra.is_empty() {
            s.push_str(",\"extra\":{");
            for (i, (k, v)) in self.extra.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                write!(s, "\"{}\":\"{}\"", json_escape(k), json_escape(v)).unwrap();
            }
            s.push('}');
        }
        s.push('}');
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const HASH_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const COMMIT: &str = "0123456789abcdef0123456789abcdef01234567";

    fn artifact() -> Artifact {
        Artifact { name: "marq-alternate.otf".into(), sha256: HASH.into(), bytes: 152_044 }
    }
    fn prov() -> Provenance {
        Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                        artifact(), vec![HASH_B.into()]).unwrap()
    }

    // P1: the full task schema answers code + commit + utc + inputs + artifact.
    #[test]
    fn p1_block_covers_the_task_schema() {
        let j = prov().to_json();
        assert!(j.contains("\"code_id\":\"k1-wire/1\""));
        assert!(j.contains(&format!("\"commit\":\"{}\"", COMMIT)));
        assert!(j.contains("\"utc\":\"2026-10-19T13:20:00Z\""));
        assert!(j.contains(&format!("\"inputs\":[\"{}\"]", HASH_B)));
        assert!(j.contains("\"name\":\"marq-alternate.otf\""));
        assert!(j.contains("\"bytes\":152044"));
    }

    // P2: serialization is deterministic (BTreeMap ordering on extra).
    #[test]
    fn p2_serialization_is_deterministic() {
        let mut p = prov();
        p.insert_extra("z", "1").unwrap();
        p.insert_extra("a", "2").unwrap();
        let j = p.to_json();
        assert!(j.find("\"a\"").unwrap() < j.find("\"z\"").unwrap());
    }

    // P3: uppercase hex normalizes to one canonical JSON (F9/G-e).
    #[test]
    fn p3_hex_case_normalizes() {
        let upper = Provenance::new(
            "k1-wire/1", &COMMIT.to_uppercase(), "2026-10-19T13:20:00Z",
            Artifact { name: "x.otf".into(), sha256: HASH.to_uppercase(), bytes: 1 },
            vec![HASH_B.to_uppercase()],
        ).unwrap();
        let lower = Provenance::new(
            "k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
            Artifact { name: "x.otf".into(), sha256: HASH.into(), bytes: 1 },
            vec![HASH_B.into()],
        ).unwrap();
        assert_eq!(upper.to_json(), lower.to_json());
        assert!(upper.to_json().contains(&COMMIT.to_string()));
    }

    // P4: real JSON escaping — quotes, backslashes, control chars (item 12).
    #[test]
    fn p4_escaping_is_valid_json() {
        assert_eq!(json_escape("a\"b\\c\nd\x1be"), "a\\\"b\\\\c\\nd\\u001be");
        let p = Provenance::new("code\"id", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec![HASH_B.into()]).unwrap();
        assert!(p.to_json().contains("\"code_id\":\"code\\\"id\""));
    }

    // P5: padded code_id is stored TRIMMED (item 13: validation and storage
    // must agree — no " k1-wire/1 " in the JSON).
    #[test]
    fn p5_code_id_stored_trimmed() {
        let p = Provenance::new("  k1-wire/1  ", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec![HASH_B.into()]).unwrap();
        assert!(p.to_json().contains("\"code_id\":\"k1-wire/1\""));
        assert!(!p.to_json().contains(" k1-wire/1 "));
    }

    // N1: bad commits refused — "HEAD", "unknown", short, long, non-hex (G-e).
    #[test]
    fn n1_bad_commit_refused() {
        for bad in ["HEAD", "unknown", "abc123f", &"a".repeat(41), &"g".repeat(40), ""] {
            assert!(Provenance::new("k1-wire/1", bad, "2026-10-19T13:20:00Z",
                                    artifact(), vec![HASH_B.into()]).is_err(),
                    "commit {:?} must fail", bad);
        }
    }

    // N2: input hashes validated; empty inputs refused (plural schema).
    #[test]
    fn n2_bad_inputs_refused() {
        assert!(Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec![]).is_err());
        assert!(Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec!["short".into()]).is_err());
        assert!(Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec![HASH_B.into(), "bad".into()]).is_err());
    }

    // N3: reserved/empty extra keys refused — duplicate JSON keys impossible
    // by construction (F10).
    #[test]
    fn n3_reserved_extra_keys_refused() {
        let mut p = prov();
        for key in ["code_id", "commit", "data_sha256", "artifact", "inputs", "utc", "extra", "  "] {
            // note: "data_sha256" is not reserved (legacy name, harmless) —
            // adjust expectation below.
            if key == "data_sha256" {
                assert!(p.insert_extra(key, "x").is_ok());
            } else {
                assert!(p.insert_extra(key, "x").is_err(), "key {:?} must fail", key);
            }
        }
    }

    // N4: bad utc refused.
    #[test]
    fn n4_bad_utc_refused() {
        for bad in ["yesterday", "2026-10-19 13:20:00", "2026-13-19T13:20:00Z",
                    "2026-10-19T25:20:00Z", "2026-10-19T13:20:00+03:00"] {
            assert!(Provenance::new("k1-wire/1", COMMIT, bad,
                                    artifact(), vec![HASH_B.into()]).is_err(),
                    "utc {:?} must fail", bad);
        }
    }

    // N5: artifact validation — empty name, bad sha refused.
    #[test]
    fn n5_bad_artifact_refused() {
        let no_name = Artifact { name: "  ".into(), sha256: HASH.into(), bytes: 1 };
        assert!(Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                                no_name, vec![HASH_B.into()]).is_err());
        let bad_sha = Artifact { name: "x.otf".into(), sha256: "nope".into(), bytes: 1 };
        assert!(Provenance::new("k1-wire/1", COMMIT, "2026-10-19T13:20:00Z",
                                bad_sha, vec![HASH_B.into()]).is_err());
    }

    // N6: empty code id refused.
    #[test]
    fn n6_empty_code_id_refused() {
        assert!(Provenance::new("   ", COMMIT, "2026-10-19T13:20:00Z",
                                artifact(), vec![HASH_B.into()]).is_err());
    }
}
