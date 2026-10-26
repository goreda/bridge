use std::{fs, path::PathBuf, process::Command};
#[test]
fn production_resume_no_refit_and_pinned_provenance() {
    let p = std::env::temp_dir().join(format!("life-e2e-{}", std::process::id()));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir(&p).unwrap();
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/kit-v415/notdef-v3/run/manifest.txt");
    let out = p.join("out");
    let run = || {
        Command::new(env!("CARGO_BIN_EXE_kni-pipeline"))
            .arg(&fixture)
            .arg(&out)
            .args([
                "--style-id",
                "Marq-Regular",
                "--jobs",
                "1",
                "--allow-partial",
                "--fallback-export-warn",
                "--checkpoint-export",
            ])
            .env(
                "KNI_SOURCE_COMMIT",
                "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
            )
            .output()
            .unwrap()
    };
    let first = run();
    assert_eq!(
        first.status.code(),
        Some(75),
        "{} {}",
        String::from_utf8_lossy(&first.stdout),
        String::from_utf8_lossy(&first.stderr)
    );
    assert!(!out.exists());
    let token = fs::read_to_string(p.join("work/runs/Marq-Regular.pending")).unwrap();
    let r = p.join("work/runs").join(token);
    let snapshot = fs::read(r.join("snapshot")).unwrap();
    // Wrong invocation conflicts without touching finalized cache or invoking fit/floor.
    let conflict = Command::new(env!("CARGO_BIN_EXE_kni-pipeline"))
        .arg(&fixture)
        .arg(&out)
        .args([
            "--style-id",
            "Marq-Regular",
            "--jobs",
            "1",
            "--allow-partial",
            "--fallback-export-warn",
            "--spacing-oohh",
            "--checkpoint-export",
        ])
        .env(
            "KNI_SOURCE_COMMIT",
            "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
        )
        .output()
        .unwrap();
    assert!(!conflict.status.success());
    assert!(String::from_utf8_lossy(&conflict.stderr).contains("PENDING_RUN_CONFLICT"));
    assert_eq!(fs::read(r.join("snapshot")).unwrap(), snapshot);
    let resume = || {
        let mut c = Command::new(env!("CARGO_BIN_EXE_kni-pipeline"));
        c.args(["resume-export", "--token"]).arg(&r).env(
            "KNI_SOURCE_COMMIT",
            "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
        );
        c
    };
    // Real process interruption releases the advisory lock and keeps sealed input intact.
    let mut child = resume()
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(100));
    child.kill().unwrap();
    child.wait().unwrap();
    assert_eq!(fs::read(r.join("snapshot")).unwrap(), snapshot);
    assert!(!out.exists());
    // An interrupted per-glyph temp is not a committed checkpoint. Locked recovery removes only that staging pattern.
    fs::write(r.join("cache/0001.tmp-999999"), b"interrupted").unwrap();
    // Metadata corruption is refused before geometry or publication, original snapshot remains usable.
    let names = fs::read(r.join("names")).unwrap();
    fs::write(r.join("names"), b"bad").unwrap();
    let bad = resume().output().unwrap();
    assert!(!bad.status.success());
    assert!(String::from_utf8_lossy(&bad.stderr).contains("EXPORT_METADATA_CORRUPT"));
    fs::write(r.join("names"), names).unwrap();
    let mut complete = false;
    for _ in 0..24 {
        let o = run();
        assert_eq!(fs::read(r.join("snapshot")).unwrap(), snapshot);
        assert!(!r.join("payload/floor.otf").exists());
        if o.status.code() != Some(75) {
            assert!(
                o.status.success(),
                "{} {}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            complete = true;
            break;
        }
    }
    assert!(complete);
    assert!(out.join("COMPLETE").is_file());
    assert!(!p.join("work/runs/Marq-Regular.pending").exists());
    let masters: Vec<_> = fs::read_dir(&out)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|e| e.path().extension().map(|x| x == "glyphs").unwrap_or(false))
        .collect();
    assert_eq!(masters.len(), 1);
    let side = fs::read_dir(&out)
        .unwrap()
        .filter_map(Result::ok)
        .find(|e| e.file_name().to_string_lossy().ends_with("provenance.json"))
        .unwrap();
    let side = fs::read_to_string(side.path()).unwrap();
    assert!(side.contains("generated_master_sha256"));
    assert!(side.contains("present"));
    let receipt = fs::read_to_string(out.join("receipt-Marq-Regular.txt")).unwrap();
    assert!(receipt.contains("export_lifecycle\tCOMPLETE"));
    assert!(!receipt.contains("master_export\tPENDING"));
    let replay = Command::new(env!("CARGO_BIN_EXE_kni-pipeline"))
        .args(["resume-export", "--token"])
        .arg(&r)
        .env(
            "KNI_SOURCE_COMMIT",
            "d20ce9dfadfbd99d70fc2aa74dbf7dbbb332ce74",
        )
        .output()
        .unwrap();
    assert!(
        replay.status.success(),
        "{}",
        String::from_utf8_lossy(&replay.stderr)
    );
    // Byte identity against the ordinary native builder and exact generated sidecar hash.
    let b = fs::read(r.join("final.otf")).unwrap();
    let (mut font, _) = kni_pipeline::otf_facts::read_otf(&b).unwrap();
    let ns = fs::read_to_string(r.join("names")).unwrap();
    for (g, n) in font.glyphs.iter_mut().zip(ns.lines()) {
        let n = kni_pipeline::export_lifecycle::decode(n).unwrap();
        g.name = n.clone();
        g.outline.glyph_id = n;
    }
    let maps = fs::read_to_string(r.join("mapping")).unwrap();
    let maps = maps
        .lines()
        .map(|l| {
            let (a, b) = l.split_once('\t').unwrap();
            (a.parse::<u32>().unwrap(), b.parse::<u16>().unwrap())
        })
        .collect::<Vec<_>>();
    let ordinary = kni_pipeline::master_companion::build(&b, &font, &maps)
        .unwrap()
        .0;
    let actual = fs::read(masters[0].path()).unwrap();
    assert_eq!(ordinary.as_bytes(), actual);
    assert!(side.contains(&kni_pipeline::export_lifecycle::hash(&actual)));
    let _ = fs::remove_dir_all(p);
}
