use kni_pipeline::export_lifecycle::*;
use std::{fs, path::PathBuf};
fn root() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "life-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir(&p).unwrap();
    p
}
fn fixture() -> (PathBuf, Session) {
    let p = root();
    let (s, _) = Session::open(&p.join("runs"), "Regular", &p.join("out"), "context").unwrap();
    fs::create_dir(s.payload()).unwrap();
    exclusive(&s.payload().join("receipt"), b"complete input").unwrap();
    (p, s)
}
#[test]
fn interrupt_before_seal_refuses_resume() {
    let (p, s) = fixture();
    assert!(s.verify().is_err());
    let (t, resume) = Session::open(&p.join("runs"), "Regular", &p.join("out"), "context").unwrap();
    assert!(resume);
    assert_eq!(t.run, s.run);
    assert!(t.verify().is_err());
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn exact_resume_and_conflict_preserve() {
    let (p, s) = fixture();
    s.seal().unwrap();
    assert!(
        Session::open(&p.join("runs"), "Regular", &p.join("out"), "wrong")
            .unwrap_err()
            .contains("PENDING_RUN_CONFLICT")
    );
    s.verify().unwrap();
    let (_, yes) = Session::open(&p.join("runs"), "Regular", &p.join("out"), "context").unwrap();
    assert!(yes);
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn corrupt_payload_and_unknown_refuse() {
    let (p, s) = fixture();
    s.seal().unwrap();
    exclusive(&s.payload().join("unknown"), b"x").unwrap();
    assert!(s.verify().unwrap_err().contains("CORRUPT"));
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn no_partial_public_atomic_commit_readback_exact_log() {
    let (p, s) = fixture();
    s.seal().unwrap();
    assert!(!s.out.exists());
    let build = s.run.join("publish");
    fs::create_dir(&build).unwrap();
    exclusive(&build.join("a.otf"), b"final").unwrap();
    exclusive(&build.join("a.glyphs"), b"master").unwrap();
    s.commit(&build).unwrap();
    s.verify_complete().unwrap();
    s.finish().unwrap();
    assert!(s.run.join("LOGGED").is_file());
    assert!(!p.join("runs/Regular.pending").exists());
    assert_eq!(fs::read_dir(&s.out).unwrap().count(), 3);
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn rename_refuses_existing_destination_without_damage() {
    let (p, s) = fixture();
    fs::create_dir(&s.out).unwrap();
    exclusive(&s.out.join("old"), b"old").unwrap();
    let b = s.run.join("publish");
    fs::create_dir(&b).unwrap();
    exclusive(&b.join("font"), b"new").unwrap();
    assert!(s.commit(&b).is_err());
    assert_eq!(regular(&s.out.join("old")).unwrap(), b"old");
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn all_styles_independent_slots_and_locks() {
    let (p, s) = fixture();
    let (t, no) = Session::open(&p.join("runs"), "Italic", &p.join("italic"), "different").unwrap();
    assert!(!no);
    let l = s.lock().unwrap();
    assert!(s.lock().is_err());
    let _t = t.lock().unwrap();
    drop(l);
    s.lock().unwrap();
    fs::remove_dir_all(p).unwrap();
}
#[cfg(unix)]
#[test]
fn symlink_payload_and_slot_refuse() {
    use std::os::unix::fs::symlink;
    let (p, s) = fixture();
    symlink(p.join("outside"), s.payload().join("evil")).unwrap();
    assert!(s.seal().is_err());
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn pending_is_distinct_from_k5_failure() {
    assert_eq!(EXIT_PENDING, 75);
    assert_ne!(
        EXIT_PENDING,
        kni_pipeline::k5_main_adapter::EXIT_NOT_APPROVED
    );
}
#[test]
fn retry_after_rename_reconciles_and_finish_idempotent() {
    let (p, s) = fixture();
    s.seal().unwrap();
    let b = s.run.join("publish");
    fs::create_dir(&b).unwrap();
    exclusive(&b.join("font"), b"x").unwrap();
    s.commit(&b).unwrap();
    let (t, resume) = Session::open(&p.join("runs"), "Regular", &s.out, "context").unwrap();
    assert!(resume);
    t.verify().unwrap();
    t.finish().unwrap();
    t.finish().unwrap();
    assert_eq!(text(&t.run.join("LOGGED")).unwrap().lines().count(), 1);
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn corruption_after_complete_refuses_cleanup() {
    let (p, s) = fixture();
    s.seal().unwrap();
    let b = s.run.join("publish");
    fs::create_dir(&b).unwrap();
    exclusive(&b.join("font"), b"x").unwrap();
    s.commit(&b).unwrap();
    fs::write(s.out.join("font"), b"tampered").unwrap();
    assert!(s.finish().is_err());
    assert!(p.join("runs/Regular.pending").exists());
    fs::remove_dir_all(p).unwrap();
}
#[cfg(unix)]
#[test]
fn symlink_parent_rejected() {
    use std::os::unix::fs::symlink;
    let p = root();
    fs::create_dir(p.join("real")).unwrap();
    symlink(p.join("real"), p.join("work")).unwrap();
    assert!(Session::open(&p.join("work/runs"), "Style", &p.join("out"), "ctx").is_err());
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn malformed_hex_refuses_without_panic() {
    assert!(unhex("é").is_err());
    assert!(unhex("x").is_err());
}
