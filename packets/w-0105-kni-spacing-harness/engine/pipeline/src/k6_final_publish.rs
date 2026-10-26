//! k6_final_publish.rs - K6 final publish: provenance bound to the real
//! final artifact bytes, published in the same all-or-nothing set.
//!
//! Add-only module (std + kni_core::sha256_hex). Base: b0b21e9a.
//!
//! Order that avoids a circular hash: the OTF bytes are final first; the
//! artifact sha256 and byte count are computed HERE from those bytes (never
//! taken from a caller claim); the provenance sidecar `<otf>.provenance.json`
//! then names that sha. The OTF never contains the sidecar hash and the
//! sidecar hash is not an input of itself.
//!
//! Inputs bound (all recomputed by the caller from real bytes):
//!   code_sha256 (running executable), manifest_sha256, source_set_sha256
//!   (sorted "name:sha256\n" rows of the stage-1 capture pins) and, when
//!   present, master_source_sha256.
//! Claimed-vs-actual: any claimed pin that differs from the recomputed one
//! refuses the whole publish (zero files), naming each mismatch.
//! Atomicity: the sidecar rides in the SAME publish set as the OTF (staged,
//! claimed, rolled back together by the injected publisher). After publish
//! the files are read back from disk and re-hashed; a mismatch removes
//! everything this call created and refuses.

use crate::k6_provenance::{Artifact, Provenance};
use kni_core::cff_reader::sha256_hex;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Pins the run recomputed from the real bytes it used.
#[derive(Debug, Clone)]
pub struct ActualPins {
    pub code_id: String,
    pub commit: String, // 40 hex
    pub utc: String,    // YYYY-MM-DDTHH:MM:SSZ
    pub code_sha256: String,
    pub manifest_sha256: String,
    pub source_set_sha256: String,
    pub master_source_sha256: Option<String>,
}

/// Pins somebody CLAIMED (env/CLI/manifest). `None` = no claim made.
#[derive(Debug, Clone, Default)]
pub struct ClaimedPins {
    pub code_sha256: Option<String>,
    pub manifest_sha256: Option<String>,
    pub source_set_sha256: Option<String>,
    pub master_source_sha256: Option<String>,
    pub artifact_sha256: Option<String>,
    pub artifact_bytes: Option<u64>,
    pub commit: Option<String>,
}

/// sha256 over sorted "name:sha256\n" rows. Order independent by construction.
pub fn source_set_sha256(pins: &std::collections::HashMap<String, String>) -> String {
    let sorted: BTreeMap<&String, &String> = pins.iter().collect();
    let mut rows = String::new();
    for (n, h) in sorted {
        rows.push_str(&format!("{n}:{h}\n"));
    }
    sha256_hex(rows.as_bytes())
}

fn same_hex(a: &str, b: &str) -> bool {
    a.trim().eq_ignore_ascii_case(b.trim())
}

/// Every claimed pin must equal the recomputed one. Collects ALL mismatches.
pub fn verify_claims(claimed: &ClaimedPins, actual: &ActualPins, artifact_sha256: &str, artifact_bytes: u64) -> Result<(), String> {
    let mut bad: Vec<String> = Vec::new();
    let mut chk = |what: &str, claim: &Option<String>, real: &str| {
        if let Some(c) = claim {
            if !same_hex(c, real) {
                bad.push(format!("{what}: claimed {c} != actual {real}"));
            }
        }
    };
    chk("code_sha256", &claimed.code_sha256, &actual.code_sha256);
    chk("manifest_sha256", &claimed.manifest_sha256, &actual.manifest_sha256);
    chk("source_set_sha256", &claimed.source_set_sha256, &actual.source_set_sha256);
    chk("commit", &claimed.commit, &actual.commit);
    chk("artifact_sha256", &claimed.artifact_sha256, artifact_sha256);
    match (&claimed.master_source_sha256, &actual.master_source_sha256) {
        (Some(c), Some(a)) if !same_hex(c, a) => bad.push(format!("master_source_sha256: claimed {c} != actual {a}")),
        (Some(c), None) => bad.push(format!("master_source_sha256: claimed {c} but the run used no master source")),
        _ => {}
    }
    if let Some(b) = claimed.artifact_bytes {
        if b != artifact_bytes {
            bad.push(format!("artifact_bytes: claimed {b} != actual {artifact_bytes}"));
        }
    }
    if bad.is_empty() { Ok(()) } else { Err(format!("K6 final publish refused: pin mismatch: {}", bad.join("; "))) }
}

pub fn sidecar_name(otf_name: &str) -> String {
    format!("{otf_name}.provenance.json")
}

/// Build the sidecar for the exact OTF bytes. Pure: no file is touched.
pub fn build_sidecar(otf_name: &str, otf_bytes: &[u8], actual: &ActualPins, claimed: &ClaimedPins) -> Result<(String, Vec<u8>), String> {
    build_sidecar_with_generated_master(otf_name, otf_bytes, actual, claimed, None)
}

/// Generated master is an OUTPUT in the same publish payload, never an input source pin.
pub fn build_sidecar_with_generated_master(otf_name: &str, otf_bytes: &[u8], actual: &ActualPins,
    claimed: &ClaimedPins, generated_master: Option<(&str, &[u8])>) -> Result<(String, Vec<u8>), String> {
    if otf_bytes.is_empty() {
        return Err("K6 final publish refused: empty artifact".into());
    }
    let artifact_sha = sha256_hex(otf_bytes);
    let artifact_len = otf_bytes.len() as u64;
    verify_claims(claimed, actual, &artifact_sha, artifact_len)?;
    let mut inputs = vec![actual.code_sha256.clone(), actual.manifest_sha256.clone(), actual.source_set_sha256.clone()];
    let mut order = String::from("code_sha256,manifest_sha256,source_set_sha256");
    if let Some(m) = &actual.master_source_sha256 {
        inputs.push(m.clone());
        order.push_str(",master_source_sha256");
    }
    let mut p = Provenance::new(&actual.code_id, &actual.commit, &actual.utc,
        Artifact { name: otf_name.to_string(), sha256: artifact_sha, bytes: artifact_len }, inputs)?;
    p.insert_extra("input_order", &order)?;
    match generated_master {
        Some((name, bytes)) => {
            p.insert_extra("generated_master_state", "present")?;
            p.insert_extra("generated_master_name", name)?;
            p.insert_extra("generated_master_sha256", &sha256_hex(bytes))?;
            p.insert_extra("generated_master_bytes", &bytes.len().to_string())?;
        }
        None => p.insert_extra("generated_master_state", "unavailable")?,
    }
    Ok((sidecar_name(otf_name), p.to_json().into_bytes()))
}

/// Publish `files` (the OTF MUST be the last entry) plus its provenance
/// sidecar as ONE set through `publish`. Returns the published paths with the
/// OTF still LAST (callers rely on that). Zero files on any refusal.
pub fn publish_with_provenance(
    dir: &Path,
    files: &[(&str, &[u8])],
    actual: &ActualPins,
    claimed: &ClaimedPins,
    publish: &dyn Fn(&Path, &[(&str, &[u8])]) -> Result<Vec<PathBuf>, String>,
) -> Result<Vec<PathBuf>, String> {
    let (otf_name, otf_bytes) = *files.last().ok_or("K6 final publish refused: empty file set")?;
    let master_name = otf_name.strip_suffix(".otf").map(|n| format!("{n}.glyphs"));
    let generated_master = files.iter().find(|(name, _)| master_name.as_deref() == Some(*name)).copied();
    let (side_name, side_bytes) = build_sidecar_with_generated_master(otf_name, otf_bytes, actual, claimed, generated_master)?;
    let mut set: Vec<(&str, &[u8])> = files[..files.len() - 1].to_vec();
    set.push((side_name.as_str(), side_bytes.as_slice()));
    set.push((otf_name, otf_bytes));
    let published = publish(dir, &set)?;
    // Readback from disk: what landed must be what was hashed.
    let verdict = readback(&published, otf_name, &side_name, otf_bytes, &side_bytes).and_then(|_| {
        for (name, expected) in files {
            let path = published.iter().find(|p| p.file_name().and_then(|n| n.to_str()) == Some(*name))
                .ok_or_else(|| format!("K6 readback: payload {name} missing"))?;
            let found = std::fs::read(path).map_err(|e| format!("K6 readback: {name}: {:?}", e.kind()))?;
            if found != *expected { return Err(format!("K6 readback: payload {name} differs - publish rolled back")); }
        }
        Ok(())
    });
    if let Err(e) = verdict {
        let mut cleanup: Vec<String> = Vec::new();
        for p in &published {
            if let Err(re) = std::fs::remove_file(p) {
                cleanup.push(format!("remove {}: {:?}", p.display(), re.kind()));
            }
        }
        return Err(if cleanup.is_empty() { e } else { format!("{e}; CLEANUP FAILED: {}", cleanup.join("; ")) });
    }
    Ok(published)
}

fn readback(published: &[PathBuf], otf_name: &str, side_name: &str, otf_bytes: &[u8], side_bytes: &[u8]) -> Result<(), String> {
    let find = |name: &str| published.iter().find(|p| p.file_name().and_then(|n| n.to_str()) == Some(name));
    let otf_path = find(otf_name).ok_or("K6 readback: OTF missing from published set")?;
    let side_path = find(side_name).ok_or("K6 readback: provenance sidecar missing from published set")?;
    let otf_disk = std::fs::read(otf_path).map_err(|e| format!("K6 readback: read OTF: {:?}", e.kind()))?;
    if sha256_hex(&otf_disk) != sha256_hex(otf_bytes) {
        return Err("K6 readback: OTF on disk differs from the hashed bytes - publish rolled back".into());
    }
    let side_disk = std::fs::read(side_path).map_err(|e| format!("K6 readback: read sidecar: {:?}", e.kind()))?;
    if side_disk != side_bytes {
        return Err("K6 readback: sidecar on disk differs from the built sidecar - publish rolled back".into());
    }
    Ok(())
}

/// Civil UTC "YYYY-MM-DDTHH:MM:SSZ" from unix seconds (no clock dependency in tests).
pub fn format_utc(secs: u64) -> String {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (h, mi, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

pub fn utc_now() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    format_utc(secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    const H1: &str = "1111111111111111111111111111111111111111111111111111111111111111";
    const H2: &str = "2222222222222222222222222222222222222222222222222222222222222222";
    const COMMIT: &str = "0123456789abcdef0123456789abcdef01234567";

    fn actual() -> ActualPins {
        ActualPins { code_id: "kni-pipeline/0.1.2".into(), commit: COMMIT.into(), utc: "2026-10-19T12:00:00Z".into(),
            code_sha256: H1.into(), manifest_sha256: H2.into(), source_set_sha256: sha256_hex(b"s"), master_source_sha256: Some(sha256_hex(b"m")) }
    }
    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("k6fp-{tag}-{}-{}", std::process::id(), utc_now()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }
    // test publisher: same semantics as the real one (all or nothing), no dependency on post_metrics
    fn plain_publish(dir: &Path, files: &[(&str, &[u8])]) -> Result<Vec<PathBuf>, String> {
        let mut out = Vec::new();
        for (n, b) in files {
            let p = dir.join(n);
            if let Err(e) = std::fs::write(&p, b) {
                for q in &out { let _ = std::fs::remove_file(q); }
                return Err(format!("write {n}: {:?}", e.kind()));
            }
            out.push(p);
        }
        Ok(out)
    }
    fn count(d: &Path) -> usize { std::fs::read_dir(d).unwrap().count() }

    #[test]
    fn generated_master_output_bound_separately_from_source_pin() {
        let d = tmpdir("generated_master");
        let master = b"{generated glyphs output}";
        let a = actual();
        publish_with_provenance(&d, &[("f.glyphs", master), ("f.otf", b"OTTO-final")], &a, &ClaimedPins::default(), &plain_publish).unwrap();
        let side = std::fs::read_to_string(d.join("f.otf.provenance.json")).unwrap();
        assert!(side.contains("generated_master_state\":\"present"));
        assert!(side.contains(&sha256_hex(master)));
        assert!(side.contains("f.glyphs"));
        assert!(side.contains(&a.master_source_sha256.unwrap()));
        let (_, no_master) = build_sidecar("f.otf", b"OTTO-final", &actual(), &ClaimedPins::default()).unwrap();
        assert!(String::from_utf8(no_master).unwrap().contains("generated_master_state\":\"unavailable"));
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn mutated_generated_master_readback_rolls_back_entire_payload() {
        let d = tmpdir("master_mutation");
        let publisher = |dir: &Path, files: &[(&str, &[u8])]| {
            let paths = plain_publish(dir, files)?;
            std::fs::write(dir.join("f.glyphs"), b"mutated").unwrap();
            Ok(paths)
        };
        let e = publish_with_provenance(&d, &[("f.glyphs", b"master"), ("f.otf", b"OTTO-final")], &actual(), &ClaimedPins::default(), &publisher).unwrap_err();
        assert!(e.contains("f.glyphs differs"));
        assert_eq!(count(&d), 0);
        std::fs::remove_dir_all(d).unwrap();
    }

    // P1: provenance names the sha of the REAL otf bytes, main-style set keeps the OTF last
    #[test]
    fn p1_sidecar_binds_real_artifact_sha_and_otf_stays_last() {
        let d = tmpdir("p1");
        let otf = b"OTTO-final-bytes".to_vec();
        let ledger = b"ledger".to_vec();
        let got = publish_with_provenance(&d, &[("ledger.tsv", &ledger[..]), ("f.otf", &otf[..])], &actual(), &ClaimedPins::default(), &plain_publish).unwrap();
        assert_eq!(got.len(), 3);
        assert_eq!(got.last().unwrap().file_name().unwrap(), "f.otf");
        let side = std::fs::read_to_string(d.join("f.otf.provenance.json")).unwrap();
        assert!(side.contains(&format!("\"sha256\":\"{}\"", sha256_hex(&otf))));
        assert!(side.contains(&format!("\"bytes\":{}", otf.len())));
        assert!(side.contains(&format!("\"commit\":\"{COMMIT}\"")));
        assert!(side.contains(H1) && side.contains(H2));
        assert!(side.contains("\"input_order\":\"code_sha256,manifest_sha256,source_set_sha256,master_source_sha256\""));
    }
    // P2: no circularity - the OTF bytes on disk are exactly the input bytes, and the sidecar hash appears in no input
    #[test]
    fn p2_no_circular_hash() {
        let d = tmpdir("p2");
        let otf = b"OTTO".to_vec();
        publish_with_provenance(&d, &[("f.otf", &otf[..])], &actual(), &ClaimedPins::default(), &plain_publish).unwrap();
        assert_eq!(std::fs::read(d.join("f.otf")).unwrap(), otf);
        let side = std::fs::read(d.join("f.otf.provenance.json")).unwrap();
        assert!(!String::from_utf8_lossy(&std::fs::read(d.join("f.otf")).unwrap()).contains(&sha256_hex(&side)));
        let (_, again) = build_sidecar("f.otf", &otf, &actual(), &ClaimedPins::default()).unwrap();
        assert_eq!(side, again, "deterministic");
    }
    // N1: claimed artifact sha that is not the real one refuses and ships zero files
    #[test]
    fn n1_claimed_artifact_sha_mismatch_refuses_zero_files() {
        let d = tmpdir("n1");
        let c = ClaimedPins { artifact_sha256: Some(sha256_hex(b"other")), ..Default::default() };
        let e = publish_with_provenance(&d, &[("f.otf", b"OTTO")], &actual(), &c, &plain_publish).unwrap_err();
        assert!(e.contains("artifact_sha256") && e.contains("pin mismatch"), "{e}");
        assert_eq!(count(&d), 0);
    }
    // N2: input mutation: claimed code/manifest/source pins differ from recomputed => all mismatches named
    #[test]
    fn n2_mutated_inputs_refuse_and_name_each_mismatch() {
        let d = tmpdir("n2");
        let c = ClaimedPins { code_sha256: Some(H2.into()), manifest_sha256: Some(H1.into()), source_set_sha256: Some(H1.into()),
            master_source_sha256: Some(H1.into()), artifact_bytes: Some(1), commit: Some("f".repeat(40)), ..Default::default() };
        let e = publish_with_provenance(&d, &[("f.otf", b"OTTO")], &actual(), &c, &plain_publish).unwrap_err();
        for k in ["code_sha256", "manifest_sha256", "source_set_sha256", "master_source_sha256", "artifact_bytes", "commit"] {
            assert!(e.contains(k), "missing {k} in {e}");
        }
        assert_eq!(count(&d), 0);
    }
    // N3: claimed master pin while the run had no master
    #[test]
    fn n3_claimed_master_without_master_refuses() {
        let mut a = actual();
        a.master_source_sha256 = None;
        let c = ClaimedPins { master_source_sha256: Some(H1.into()), ..Default::default() };
        let e = build_sidecar("f.otf", b"OTTO", &a, &c).unwrap_err();
        assert!(e.contains("no master source"), "{e}");
    }
    // N4: matching claims (case-insensitive hex) pass
    #[test]
    fn n4_matching_claims_pass_case_insensitive() {
        let c = ClaimedPins { code_sha256: Some(H1.to_uppercase()), artifact_sha256: Some(sha256_hex(b"OTTO").to_uppercase()), artifact_bytes: Some(4), ..Default::default() };
        assert!(build_sidecar("f.otf", b"OTTO", &actual(), &c).is_ok());
    }
    // N5: atomic abort: publisher fails => nothing remains, error passes through
    #[test]
    fn n5_publisher_failure_leaves_nothing() {
        let d = tmpdir("n5");
        let failing = |dir: &Path, files: &[(&str, &[u8])]| -> Result<Vec<PathBuf>, String> {
            std::fs::write(dir.join(files[0].0), files[0].1).unwrap();
            std::fs::remove_file(dir.join(files[0].0)).unwrap();
            Err("publish: simulated claim failure".into())
        };
        let e = publish_with_provenance(&d, &[("a.tsv", b"a"), ("f.otf", b"OTTO")], &actual(), &ClaimedPins::default(), &failing).unwrap_err();
        assert!(e.contains("simulated claim failure"));
        assert_eq!(count(&d), 0);
    }
    // N6: readback catches a publisher that wrote different bytes: everything removed
    #[test]
    fn n6_readback_mismatch_rolls_back() {
        let d = tmpdir("n6");
        let corrupting = |dir: &Path, files: &[(&str, &[u8])]| -> Result<Vec<PathBuf>, String> {
            let mut out = Vec::new();
            for (n, b) in files {
                let p = dir.join(n);
                let mut bytes = b.to_vec();
                if n.ends_with(".otf") { bytes.push(0); }
                std::fs::write(&p, bytes).unwrap();
                out.push(p);
            }
            Ok(out)
        };
        let e = publish_with_provenance(&d, &[("f.otf", b"OTTO")], &actual(), &ClaimedPins::default(), &corrupting).unwrap_err();
        assert!(e.contains("differs from the hashed bytes"), "{e}");
        assert_eq!(count(&d), 0);
    }
    // N7: publisher that drops the sidecar from its result is refused
    #[test]
    fn n7_missing_sidecar_in_result_refuses() {
        let d = tmpdir("n7");
        let dropping = |dir: &Path, files: &[(&str, &[u8])]| -> Result<Vec<PathBuf>, String> {
            let mut out = Vec::new();
            for (n, b) in files {
                let p = dir.join(n);
                std::fs::write(&p, b).unwrap();
                if !n.ends_with(".json") { out.push(p); }
            }
            Ok(out)
        };
        let e = publish_with_provenance(&d, &[("f.otf", b"OTTO")], &actual(), &ClaimedPins::default(), &dropping).unwrap_err();
        assert!(e.contains("sidecar missing"), "{e}");
    }
    // N8: empty artifact and bad commit are refused before any file
    #[test]
    fn n8_empty_artifact_and_bad_commit_refuse() {
        let d = tmpdir("n8");
        assert!(publish_with_provenance(&d, &[("f.otf", b"")], &actual(), &ClaimedPins::default(), &plain_publish).is_err());
        let mut a = actual();
        a.commit = "HEAD".into();
        assert!(publish_with_provenance(&d, &[("f.otf", b"OTTO")], &a, &ClaimedPins::default(), &plain_publish).is_err());
        assert_eq!(count(&d), 0);
    }
    // N9: source set hash is order independent and sensitive to a single changed pin
    #[test]
    fn n9_source_set_hash_order_independent_and_mutation_sensitive() {
        let mut a = std::collections::HashMap::new();
        a.insert("A".to_string(), H1.to_string());
        a.insert("B".to_string(), H2.to_string());
        let mut b = std::collections::HashMap::new();
        b.insert("B".to_string(), H2.to_string());
        b.insert("A".to_string(), H1.to_string());
        assert_eq!(source_set_sha256(&a), source_set_sha256(&b));
        b.insert("A".to_string(), H2.to_string());
        assert_ne!(source_set_sha256(&a), source_set_sha256(&b));
    }
    #[test]
    fn utc_format_known_values() {
        assert_eq!(format_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_utc(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(format_utc(1_792_411_200), "2026-10-19T12:00:00Z");
    }
}
