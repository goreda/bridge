use kni_learning::prior::{Cell, Priors};
use kni_learning::*;

fn prov(font: &str, certified: bool) -> Provenance {
    Provenance { font_id: font.into(), run_id: "r".into(), receipt_id: "x".into(), tested_sha: "s".into(), declared_cap_u: 700.0, measured_cap_px: 350.0, certified }
}
fn obs(font: &str, bucket: &str, n: u64, mean: f64) -> Obs {
    Obs { key: vec![("wall".into(), bucket.into())], n, sum: mean * n as f64, sumsq: mean * mean * n as f64, prov: prov(font, true) }
}
fn store() -> Store {
    Store::new(1, &["wall", "class"]).unwrap()
}
fn tmp(n: &str) -> String {
    format!("{}/kni-learning-{}-{}", std::env::temp_dir().display(), std::process::id(), n)
}

#[test]
fn session_k_is_declared_over_measured() {
    assert_eq!(prov("a", true).session_k(), 2.0);
}

#[test]
fn schema_whitelist_rejects_forbidden_and_unknown_fields() {
    for bad in ["glyph", "glyph_name", "x_coord", "kern_value", "Unicode", "family_name"] {
        assert!(matches!(Store::new(1, &[bad]), Err(StoreError::ForbiddenField(_))), "{bad}");
    }
    let mut s = store();
    let mut o = obs("a", "b", 1, 1.0);
    o.key = vec![("glyph".into(), "A".into())];
    assert!(matches!(s.append(o.clone()), Err(StoreError::ForbiddenField(_))));
    o.key = vec![("other".into(), "A".into())];
    assert!(matches!(s.append(o), Err(StoreError::UnknownField(_))));
    // hand-edited file that declares a forbidden field is refused on read
    assert!(Store::parse("KNI-LEARN\tschema=1\tfields=glyph\n").is_err());
}

#[test]
fn uncertified_runs_are_refused() {
    let mut s = store();
    let mut o = obs("a", "b", 1, 1.0);
    o.prov.certified = false;
    assert_eq!(s.append(o), Err(StoreError::Uncertified));
}

#[test]
fn roundtrip_pin_and_chain() {
    let mut s = store();
    s.append(obs("a", "b1", 3, 0.5)).unwrap();
    s.append(obs("b", "b1", 2, 0.7)).unwrap();
    let text = s.serialize();
    assert_eq!(Store::parse(&text).unwrap(), s);
    // tamper with an earlier record: chain breaks
    let bad = text.replacen("n=3", "n=4", 1);
    assert!(matches!(Store::parse(&bad), Err(StoreError::ChainBroken(_))));
    // delete the first record: chain breaks
    let mut lines: Vec<&str> = text.lines().collect();
    lines.remove(1);
    assert!(Store::parse(&lines.join("\n")).is_err());
}

#[test]
fn add_only_persistence_refuses_rewrite() {
    let p = tmp("addonly");
    let mut s = store();
    s.append(obs("a", "b1", 1, 1.0)).unwrap();
    s.save_new(&p).unwrap();
    s.append(obs("b", "b1", 1, 2.0)).unwrap();
    s.save_append(&p).unwrap();
    let mut other = store();
    other.append(obs("z", "b9", 1, 9.0)).unwrap();
    assert!(other.save_append(&p).is_err());
    let _ = std::fs::remove_file(&p);
}

#[test]
fn pin_mismatch_and_bad_files_are_cold() {
    let p = tmp("pin");
    let mut s = store();
    s.append(obs("a", "b1", 1, 1.0)).unwrap();
    s.save_new(&p).unwrap();
    let (pin, bytes) = s.pin();
    assert_eq!(bytes, std::fs::read(&p).unwrap().len());
    assert!(matches!(Store::load(&p, Some(&pin)), Loaded::Warm(_)));
    assert!(matches!(Store::load(&p, Some("00")), Loaded::Cold(_)));
    // cold start: absent, empty, header-only, corrupt
    assert!(matches!(Store::load(&tmp("missing"), None), Loaded::Cold(_)));
    std::fs::write(&p, "").unwrap();
    assert!(matches!(Store::load(&p, None), Loaded::Cold(_)));
    std::fs::write(&p, store().serialize()).unwrap();
    assert!(matches!(Store::load(&p, None), Loaded::Cold(_)));
    std::fs::write(&p, "garbage\x00\x01").unwrap();
    assert!(matches!(Store::load(&p, None), Loaded::Cold(_)));
    let _ = std::fs::remove_file(&p);
}

#[test]
fn sha256_known_answers() {
    assert_eq!(sha256::sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert_eq!(sha256::sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

#[test]
fn no_priors_below_two_fonts() {
    let mut s = store();
    s.append(obs("a", "b1", 10, 1.0)).unwrap();
    assert!(Priors::from_store(&s).is_empty());
}

#[test]
fn equal_weight_per_font_no_single_font_leak() {
    let mut s = store();
    s.append(obs("big", "b1", 100000, 1.0)).unwrap();
    s.append(obs("small", "b1", 1, 3.0)).unwrap();
    let p = Priors::from_store(&s);
    let k = vec![("wall".to_string(), "b1".to_string())];
    assert_eq!(p.lookup(&k).unwrap().mean, 2.0);
    // a bucket seen by one font only is UNSEEN even when other buckets have priors
    s.append(obs("big", "only_big", 5, 9.0)).unwrap();
    let p = Priors::from_store(&s);
    assert!(p.lookup(&vec![("wall".to_string(), "only_big".to_string())]).is_err());
}

#[test]
fn leave_font_out_synthetic() {
    let mut s = store();
    for f in ["a", "b", "c"] {
        s.append(obs(f, "shared", 4, 1.0)).unwrap();
        s.append(obs(f, &format!("own_{f}"), 4, 5.0)).unwrap();
    }
    let cells = |f: &str| -> Vec<Cell> {
        vec![
            Cell { key: vec![("wall".into(), "shared".into())], observed: 1.0, baseline_pred: 2.0 },
            Cell { key: vec![("wall".into(), format!("own_{f}"))], observed: 5.0, baseline_pred: 5.0 },
        ]
    };
    let r = leave_font_out(&s, &cells);
    assert_eq!(r.len(), 3);
    for rep in &r {
        assert_eq!(rep.unseen, 1); // own bucket is unseen when the font is left out
        assert_eq!(rep.prior_abs_err, 0.0);
        assert_eq!(rep.baseline_abs_err, 1.0);
        assert!(rep.beats_baseline);
    }
    // only unseen cells: never a win
    let none = |_: &str| vec![Cell { key: vec![("wall".into(), "zzz".into())], observed: 1.0, baseline_pred: 9.0 }];
    assert!(leave_font_out(&s, &none).iter().all(|r| !r.beats_baseline));
}

#[test]
fn shrinkage_uses_data_variance_not_constants() {
    let mut s = store();
    s.append(obs("a", "b1", 4, 0.0)).unwrap();
    s.append(obs("b", "b1", 4, 10.0)).unwrap();
    let p = Priors::from_store(&s);
    let pr = p.lookup(&vec![("wall".to_string(), "b1".to_string())]).unwrap();
    assert_eq!(pr.mean, 5.0);
    assert_eq!(pr.between_var, 50.0);
    // no own data: prior
    assert_eq!(pr.shrink(0, 0.0, 0.0), 5.0);
    // zero own spread: own mean dominates only as far as tau2 allows (here fully)
    assert_eq!(pr.shrink(3, 30.0, 300.0), 10.0);
    // a single observation carries no variance estimate: stay at the prior
    assert_eq!(pr.shrink(1, 10.0, 100.0), 5.0);
    // two noisy observations (0 and 20): pulled back toward the prior
    let noisy = pr.shrink(2, 20.0, 400.0);
    assert!(noisy > 5.0 && noisy < 10.0, "{noisy}");
    // more data of the same spread moves it toward the font's own mean
    let more = pr.shrink(100, 1000.0, 50000.0);
    assert!(more > noisy && more < 10.0, "{more}");
}
