//! B production caller: verify final on-disk artifact binding, mutation refusal,
//! and unchanged OTF bytes when provenance is enabled.
use std::{fs, path::{Path, PathBuf}, process::{Command, Output}};
fn copy(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap();
    for e in fs::read_dir(src).unwrap() { let e=e.unwrap();
        if e.path().is_dir() { copy(&e.path(), &dst.join(e.file_name())); }
        else { fs::copy(e.path(), dst.join(e.file_name())).unwrap(); }
    }
}
fn run(work: &Path, tag: &str, pin: bool, claim: bool) -> (PathBuf, Output) {
    let out=work.join(tag);
    let mut c=Command::new(env!("CARGO_BIN_EXE_kni-pipeline"));
    for key in ["KNI_SOURCE_COMMIT", "KNI_CLAIMED_CODE_SHA256", "KNI_CLAIMED_MANIFEST_SHA256", "KNI_CLAIMED_SOURCE_SET_SHA256", "KNI_CLAIMED_MASTER_SHA256", "KNI_CLAIMED_ARTIFACT_SHA256", "KNI_CLAIMED_ARTIFACT_BYTES", "KNI_CLAIMED_COMMIT"] { c.env_remove(key); }
    if pin { c.env("KNI_SOURCE_COMMIT", "0123456789abcdef0123456789abcdef01234567"); }
    if claim { c.env("KNI_CLAIMED_ARTIFACT_SHA256", "0".repeat(64)); }
    let r=c.arg(work.join("manifest.txt")).arg(&out).args(["--style-id", "Marq-Regular", "--allow-partial", "--fallback-export-warn"]).output().unwrap();
    (out,r)
}
#[test]
fn final_artifact_binding_no_otf_delta_and_claim_mismatch_zero_publish() {
    let work=std::env::temp_dir().join(format!("k6-b-e2e-{}",std::process::id()));
    let _=fs::remove_dir_all(&work);
    copy(&Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run"),&work);
    let (base,b)=run(&work,"base",false,false); assert!(b.status.success(),"{}",String::from_utf8_lossy(&b.stderr));
    let (with,p)=run(&work,"pinned",true,false); assert!(p.status.success(),"{}",String::from_utf8_lossy(&p.stderr));
    let font="font-Marq-Regular.otf";
    let bytes=fs::read(with.join(font)).unwrap();
    assert_eq!(bytes,fs::read(base.join(font)).unwrap(),"K6 changed font bytes");
    let side=fs::read_to_string(with.join(format!("{font}.provenance.json"))).unwrap();
    assert!(side.contains(&kni_core::cff_reader::sha256_hex(&bytes)));
    assert!(side.contains(&format!("\"bytes\":{}",bytes.len())));
    assert!(side.contains("0123456789abcdef0123456789abcdef01234567"));
    let (bad,b)=run(&work,"bad",true,true); assert!(!b.status.success());
    assert!(String::from_utf8_lossy(&b.stderr).contains("artifact_sha256"));
    assert!(!bad.join(font).exists()); assert!(!bad.join(format!("{font}.provenance.json")).exists());
    let (missing,m)=run(&work,"missing",false,true); assert!(!m.status.success());
    assert!(!missing.join(font).exists());
    fs::remove_dir_all(work).unwrap();
}
