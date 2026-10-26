use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
fn copy(a: &Path, b: &Path) {
    fs::create_dir_all(b).unwrap();
    for e in fs::read_dir(a).unwrap() {
        let e = e.unwrap();
        if e.path().is_dir() {
            copy(&e.path(), &b.join(e.file_name()))
        } else {
            fs::copy(e.path(), b.join(e.file_name())).unwrap();
        }
    }
}
#[test]
fn actual_allstyles_kill_resume_gate_and_replay() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(4)
        .unwrap()
        .to_path_buf();
    if !repo.join("tools/check-receipt-schema.py").is_file() {
        panic!("current caller closure files required");
    }
    let p = std::env::temp_dir().join(format!("life-callers-{}", std::process::id()));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir(&p).unwrap();
    let source =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/kit-v415/notdef-v3/run");
    let coll = p.join("collection");
    for sub in ["Regular", "Italic"] {
        let s = coll.join("Marq").join(sub);
        copy(&source, &s);
        let m = fs::read_to_string(s.join("manifest.txt"))
            .unwrap()
            .replace("Regular", sub);
        fs::write(s.join("manifest.txt"), m).unwrap();
    }
    let out = p.join("run");
    let adapter = repo.join("tools/kni-style-adapter.sh");
    let mut first = Command::new("bash")
        .arg(&adapter)
        .args(["Marq/Regular"])
        .arg(out.join("Marq/Regular"))
        .env("KNI_COLLECTION", &coll)
        .env("KNI_PIPELINE", env!("CARGO_BIN_EXE_kni-pipeline"))
        .env(
            "KNI_SOURCE_COMMIT",
            "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
        )
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let slot = out.join("Marq/work/runs/Marq-Regular.pending");
    let start = Instant::now();
    while !slot.is_file() {
        assert!(start.elapsed() < Duration::from_secs(20));
        std::thread::sleep(Duration::from_millis(10));
    }
    let token = fs::read_to_string(&slot).unwrap();
    let run = slot.parent().unwrap().join(token);
    while !run.join("METADATA_SEALED").is_file() {
        assert!(start.elapsed() < Duration::from_secs(20));
        std::thread::sleep(Duration::from_millis(10));
    }
    // Kill actual child engine and adapter, then wait: no detached worker survives the test.
    let pid = first.id();
    let children = Command::new("ps")
        .args(["-eo", "pid=,ppid="])
        .output()
        .unwrap();
    for l in String::from_utf8(children.stdout).unwrap().lines() {
        let v = l.split_whitespace().collect::<Vec<_>>();
        if v.len() == 2 && v[1] == pid.to_string() {
            Command::new("kill").args(["-KILL", v[0]]).status().unwrap();
        }
    }
    first.kill().unwrap();
    first.wait().unwrap();
    assert!(!out.join("Marq/Regular").exists());
    // Mark root using the actual caller on a new two-style root. Existing pending state is kept.
    let logs = out.join(".logs");
    fs::create_dir(&logs).unwrap();
    let eng = env!("CARGO_BIN_EXE_kni-pipeline");
    let hash = kni_pipeline::export_lifecycle::hash(&fs::read(eng).unwrap());
    fs::write(
        logs.join(".lifecycle-root"),
        format!("{eng}|{hash}|{}\n", coll.display()),
    )
    .unwrap();
    let multi = || {
        Command::new("bash")
            .arg(repo.join("tools/run-multi-style.sh"))
            .arg(&out)
            .env("KNI_COLLECTION", &coll)
            .env("KNI_PIPELINE", eng)
            .env(
                "KNI_SOURCE_COMMIT",
                "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
            )
            .env("JOBS", "1")
            .env("HEARTBEAT", "0")
            .output()
            .unwrap()
    };
    let o = multi();
    assert!(
        o.status.success(),
        "{} {}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    assert!(String::from_utf8_lossy(&o.stdout).contains("OK (2/2 styles)"));
    let before = fs::read(out.join("Marq/Regular/font-Marq-Regular.otf")).unwrap();
    let o = multi();
    assert!(o.status.success());
    assert_eq!(
        before,
        fs::read(out.join("Marq/Regular/font-Marq-Regular.otf")).unwrap()
    );
    assert!(out.join("Marq/Italic/COMPLETE").is_file());
    fs::write(out.join(".logs/Marq/Italic.rc"), b"75").unwrap();
    let gate = Command::new("bash")
        .arg(repo.join("tools/verify-all-styles-ok.sh"))
        .arg(&out)
        .env("KNI_COLLECTION", coll)
        .output()
        .unwrap();
    assert!(!gate.status.success());
    assert!(String::from_utf8_lossy(&gate.stdout).contains("adapter not complete"));
    fs::remove_dir_all(p).unwrap();
}
#[test]
fn run_command_never_zips_failed_or_pending_run() {
    use std::os::unix::fs::PermissionsExt;
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(4)
        .unwrap()
        .to_path_buf();
    let p = std::env::temp_dir().join(format!("life-nozip-{}", std::process::id()));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir_all(p.join("kni-kit/out8-runkit-v2/engine")).unwrap();
    fs::create_dir(p.join("tools")).unwrap();
    fs::create_dir(p.join("bin")).unwrap();
    fs::copy(
        repo.join("kni-kit/RUN.command"),
        p.join("kni-kit/RUN.command"),
    )
    .unwrap();
    for (file, body) in [
        (p.join("bin/cargo"), "#!/bin/sh\nexit 0\n"),
        (
            p.join("tools/run-multi-style.sh"),
            "#!/bin/sh\nmkdir -p \"$1/.logs\"\nexit 75\n",
        ),
    ] {
        fs::write(&file, body).unwrap();
        fs::set_permissions(file, fs::Permissions::from_mode(0o755)).unwrap();
    }
    let o = Command::new("bash")
        .arg(p.join("kni-kit/RUN.command"))
        .env(
            "PATH",
            format!(
                "{}:{}",
                p.join("bin").display(),
                std::env::var("PATH").unwrap()
            ),
        )
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(75));
    assert!(p.join("kni-kit/work/all-styles.pending").is_file());
    assert!(!fs::read_dir(p.join("kni-kit"))
        .unwrap()
        .filter_map(Result::ok)
        .any(|e| e.path().extension().map(|x| x == "zip").unwrap_or(false)));
    fs::remove_dir_all(p).unwrap();
}
