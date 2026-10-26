use super::*;
use kni_pipeline::export_lifecycle as life;
use std::cell::RefCell;
thread_local! {pub(super) static EXPORT_SESSION:RefCell<Option<PathBuf>>=const{RefCell::new(None)};}
pub(super) fn encode_export_pins(
    a: &k6_final_publish::ActualPins,
    c: &k6_final_publish::ClaimedPins,
) -> String {
    let values = vec![
        Some(a.code_id.clone()),
        Some(a.commit.clone()),
        Some(a.utc.clone()),
        Some(a.code_sha256.clone()),
        Some(a.manifest_sha256.clone()),
        Some(a.source_set_sha256.clone()),
        a.master_source_sha256.clone(),
        c.code_sha256.clone(),
        c.manifest_sha256.clone(),
        c.source_set_sha256.clone(),
        c.master_source_sha256.clone(),
        c.artifact_sha256.clone(),
        c.artifact_bytes.map(|n| n.to_string()),
        c.commit.clone(),
    ];
    values
        .iter()
        .map(|v| {
            v.as_ref()
                .map(|s| format!("+{}", life::hex(s.as_bytes())))
                .unwrap_or_else(|| "-".into())
        })
        .collect::<Vec<_>>()
        .join("\n")
}
fn pins(
    s: &str,
) -> Result<Option<(k6_final_publish::ActualPins, k6_final_publish::ClaimedPins)>, String> {
    if s.is_empty() {
        return Ok(None);
    }
    let v = s
        .lines()
        .map(|l| {
            if l == "-" {
                Ok(None)
            } else {
                Ok(Some(life::decode(
                    l.strip_prefix('+').ok_or("EXPORT_PIN_FORMAT")?,
                )?))
            }
        })
        .collect::<Result<Vec<_>, String>>()?;
    if v.len() != 14 {
        return Err("EXPORT_PIN_COUNT".into());
    }
    let r = |i: usize| {
        v[i].clone()
            .ok_or_else(|| "EXPORT_PIN_REQUIRED".to_string())
    };
    Ok(Some((
        k6_final_publish::ActualPins {
            code_id: r(0)?,
            commit: r(1)?,
            utc: r(2)?,
            code_sha256: r(3)?,
            manifest_sha256: r(4)?,
            source_set_sha256: r(5)?,
            master_source_sha256: v[6].clone(),
        },
        k6_final_publish::ClaimedPins {
            code_sha256: v[7].clone(),
            manifest_sha256: v[8].clone(),
            source_set_sha256: v[9].clone(),
            master_source_sha256: v[10].clone(),
            artifact_sha256: v[11].clone(),
            artifact_bytes: v[12]
                .as_ref()
                .map(|s| s.parse::<u64>().map_err(|_| "EXPORT_PIN_BYTES".to_string()))
                .transpose()?,
            commit: v[13].clone(),
        },
    )))
}
fn fingerprint(args: &[String], m: &Manifest) -> Result<String, String> {
    let mut paths: Vec<PathBuf> = m.glyphs.iter().map(|g| g.image.clone()).collect();
    paths.extend(m.references.iter().map(|r| r.1.clone()));
    paths.extend(m.notdef.iter().map(|v| v.file.clone()));
    paths.extend(m.capture_manifest.iter().map(|v| v.0.clone()));
    paths.extend(m.style_overrides.iter().map(|v| v.0.clone()));
    paths.extend(m.stage1_cache.iter().cloned());
    paths.extend(m.auto_sb_class_table.iter().cloned());
    paths.extend(m.auto_sb_pool.iter().cloned());
    paths.extend(m.learned_store.iter().map(|v| v.0.clone()));
    paths.extend(m.learned_gate_evidence.iter().cloned());
    paths.extend(m.space_evidence.iter().map(|v| v.path.clone()));
    if let Some(v) = &m.space_evidence {
        let spec = space_spec::parse_spec(
            &life::text(&v.path)?,
            v.path.parent().unwrap_or(Path::new(".")),
        )?;
        paths.extend(
            spec.hsh
                .iter()
                .chain(spec.hhh.iter())
                .map(|t| t.path.clone()),
        );
        paths.extend(spec.slope_tiles.iter().map(|t| t.tile.path.clone()));
        paths.extend(spec.scale_record.iter().map(|t| t.path.clone()));
    }
    if let Some(v) = &m.notdef {
        let t = life::text(&v.file)?;
        for l in t.lines() {
            let f = l.split('\t').collect::<Vec<_>>();
            if f.first() == Some(&"pixel_source") && f.len() == 5 {
                paths.push(v.file.parent().unwrap_or(Path::new(".")).join(f[3]));
            }
        }
    }
    if let Some((path, _)) = &m.capture_manifest {
        for line in life::text(path)?.lines() {
            let f = line.split('\t').collect::<Vec<_>>();
            if f.first() == Some(&"source") && f.len() == 4 {
                paths.push(
                    Path::new(&args[1])
                        .parent()
                        .unwrap_or(Path::new("."))
                        .join(f[2]),
                );
            }
        }
    }
    for flag in ["--auto-sb-class-table", "--auto-sb-pool"] {
        if let Some(i) = args.iter().position(|x| x == flag) {
            paths.push(PathBuf::from(args.get(i + 1).ok_or("EXPORT_CLI_VALUE")?));
        }
    }
    paths.sort();
    paths.dedup();
    let mut lineage = format!(
        "args={args:?}\nmanifest={}\nexe={}\nenv={:?}",
        life::hash(&life::regular(Path::new(&args[1]))?),
        life::hash(&life::regular(
            &std::env::current_exe().map_err(|e| e.to_string())?
        )?),
        std::env::vars()
            .filter(|(k, _)| k.starts_with("KNI_") || k.starts_with("PARTS_"))
            .collect::<std::collections::BTreeMap<_, _>>()
    );
    for p in paths {
        lineage.push_str(&format!(
            "\n{}:{}",
            p.display(),
            life::hash(&life::regular(&p)?)
        ));
    }
    Ok(life::hash(lineage.as_bytes()))
}
pub(super) fn run() -> Result<life::Outcome, String> {
    match execute() {
        Ok(r) => Ok(life::Outcome::Complete(r)),
        Err(e) if e.starts_with("EXPORT_PENDING ") => Ok(life::Outcome::Pending(e)),
        Err(e) => Err(e),
    }
}
fn execute() -> Result<String, String> {
    let mut args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("new-run") {
        if args.len() < 7 || args[2] != "--retire-token" {
            return Err("usage: new-run --retire-token PATH MANIFEST OUTPUT --style-id STYLE --checkpoint-export".into());
        }
        let run = PathBuf::from(&args[3]);
        life::directory(&run)?;
        let old = life::Session {
            out: PathBuf::from(life::decode(&life::text(&run.join("destination"))?)?),
            context: life::text(&run.join("context"))?,
            run,
        };
        let _lock = old.lock()?;
        let style = life::text(&old.run.join("style"))?;
        let slot = old
            .run
            .parent()
            .ok_or("EXPORT_PARENT")?
            .join(format!("{style}.pending"));
        if life::text(&slot)? != old.token() {
            return Err("EXPORT_RETIRE_CONFLICT".into());
        }
        life::exclusive(&old.run.join("RETIRED"), b"explicit new-run --retire-token")?;
        fs::remove_file(slot).map_err(|e| e.to_string())?;
        args.drain(1..4);
    }
    if args.get(1).map(String::as_str) == Some("resume-export") {
        return explicit_resume(&args);
    }
    let enabled = if let Some(i) = args.iter().position(|a| a == "--checkpoint-export") {
        args.remove(i);
        true
    } else {
        false
    };
    if !enabled {
        return run_inner(args);
    }
    // Both public CLI argument orders are supported, including the all-styles adapter flags-first form.
    let mut positional = Vec::new();
    let mut flags = Vec::new();
    let mut i = 1;
    while i < args.len() {
        let a = &args[i];
        if a.starts_with("--") {
            flags.push(a.clone());
            if [
                "--style-id",
                "--jobs",
                "--pair-visual-dir",
                "--auto-sb",
                "--auto-sb-class-table",
                "--auto-sb-pool",
                "--auto-sb-offset-lsb",
                "--auto-sb-offset-rsb",
                "--tie-break",
            ]
            .contains(&a.as_str())
            {
                i += 1;
                flags.push(args.get(i).ok_or("EXPORT_CLI_VALUE")?.clone());
            }
        } else {
            positional.push(a.clone());
        }
        i += 1;
    }
    if positional.len() != 2 {
        return Err("EXPORT_POSITIONAL: expected manifest and destination".into());
    }
    args = std::iter::once(args[0].clone())
        .chain(positional)
        .chain(flags)
        .collect();
    if args.len() < 5 {
        return Err("usage: MANIFEST OUTPUT --style-id STYLE --checkpoint-export".into());
    }
    let style = args
        .iter()
        .position(|a| a == "--style-id")
        .and_then(|i| args.get(i + 1))
        .ok_or("EXPORT_STYLE_REQUIRED")?
        .clone();
    let manifest = PathBuf::from(&args[1]);
    let out = absolute(Path::new(&args[2]))?;
    let m = parse_manifest(
        &fs::read_to_string(&manifest).map_err(|e| e.to_string())?,
        manifest.parent().unwrap_or(Path::new(".")),
    )?;
    let context = fingerprint(&args, &m)?;
    let root = out.parent().ok_or("EXPORT_PARENT")?.join("work/runs");
    let (session, resume) = life::Session::open(&root, &style, &out, &context)?;
    let _lock = session.lock()?;
    if resume {
        println!(
            "resume AUTO reason pending_run_pins_match token {}",
            session.token()
        );
        if out.exists() {
            verify_all(&session)?;
            session.finish()?;
            return completed_receipt(&session);
        }
    } else {
        let mut inner = args.clone();
        inner[2] = session.payload().to_string_lossy().into();
        EXPORT_SESSION.with(|s| *s.borrow_mut() = Some(session.run.clone()));
        let result = run_inner(inner);
        EXPORT_SESSION.with(|s| *s.borrow_mut() = None);
        let receipt = result?;
        if fingerprint(&args, &m)? != context {
            return Err("PENDING_RUN_CONFLICT: inputs changed during fit".into());
        }
        if !session.run.join("final.otf").is_file() {
            return Err(
                "EXPORT_NO_FINAL_SNAPSHOT: this run path did not reach native master emission"
                    .into(),
            );
        }
        life::exclusive(&session.run.join("result-receipt"), receipt.as_bytes())?;
        life::exclusive(
            &session.run.join("invocation"),
            args.iter()
                .map(|a| life::hex(a.as_bytes()))
                .collect::<Vec<_>>()
                .join("\n")
                .as_bytes(),
        )?;
        let id = run_audit::RunIdentity {
            population_sha256: m.population_sha256.clone(),
            family: m.family.clone(),
            subfamily: m.subfamily.clone(),
            postscript_name: m.postscript_name.clone(),
            style_id: style.clone(),
            emitter: run_audit::EMITTER.into(),
        };
        life::exclusive(
            &session.run.join("audit-identity"),
            [
                id.population_sha256,
                id.family,
                id.subfamily,
                id.postscript_name,
                id.style_id,
                id.emitter,
            ]
            .iter()
            .map(|v| life::hex(v.as_bytes()))
            .collect::<Vec<_>>()
            .join("\n")
            .as_bytes(),
        )?;
        seal_all(&session)?;
    }
    session.verify()?;
    resume_one(&session)
}
fn absolute(p: &Path) -> Result<PathBuf, String> {
    if p.is_absolute() {
        Ok(p.into())
    } else {
        Ok(std::env::current_dir().map_err(|e| e.to_string())?.join(p))
    }
}
fn seal_all(s: &life::Session) -> Result<(), String> {
    let mut m = life::tree_manifest(&s.payload())?;
    for n in [
        "final.otf",
        "names",
        "mapping",
        "otf-name",
        "provenance",
        "result-receipt",
        "context",
        "destination",
        "style",
        "invocation",
        "audit-identity",
    ] {
        let b = life::regular(&s.run.join(n))?;
        m.push_str(&format!("{n}\\t{}\\n", life::hash(&b)));
    }
    life::exclusive(&s.run.join("metadata-seal"), m.as_bytes())?;
    s.seal()?;
    life::exclusive(
        &s.run.join("METADATA_SEALED"),
        life::hash(m.as_bytes()).as_bytes(),
    )
}
fn verify_all(s: &life::Session) -> Result<(), String> {
    s.verify()?;
    let mut m = life::tree_manifest(&s.payload())?;
    for n in [
        "final.otf",
        "names",
        "mapping",
        "otf-name",
        "provenance",
        "result-receipt",
        "context",
        "destination",
        "style",
        "invocation",
        "audit-identity",
    ] {
        let b = life::regular(&s.run.join(n))?;
        m.push_str(&format!("{n}\\t{}\\n", life::hash(&b)));
    }
    if life::text(&s.run.join("METADATA_SEALED"))? != life::hash(m.as_bytes())
        || life::text(&s.run.join("metadata-seal"))? != m
    {
        return Err("EXPORT_METADATA_CORRUPT".into());
    }
    Ok(())
}
fn explicit_resume(a: &[String]) -> Result<String, String> {
    if a.len() != 4 || a[2] != "--token" {
        return Err("usage: resume-export --token /absolute/work/runs/TOKEN".into());
    }
    let run = PathBuf::from(&a[3]);
    life::directory(&run)?;
    let context = life::text(&run.join("context"))?;
    let out = PathBuf::from(life::decode(&life::text(&run.join("destination"))?)?);
    let s = life::Session { run, out, context };
    let _lock = s.lock()?;
    verify_all(&s)?;
    resume_one(&s)
}
fn resume_one(s: &life::Session) -> Result<String, String> {
    verify_all(s)?;
    let args = life::text(&s.run.join("invocation"))?
        .lines()
        .map(life::decode)
        .collect::<Result<Vec<_>, _>>()?;
    let mp = Path::new(&args[1]);
    let m = parse_manifest(&life::text(mp)?, mp.parent().unwrap_or(Path::new(".")))?;
    if fingerprint(&args, &m)? != s.context {
        return Err("PENDING_RUN_CONFLICT".into());
    }
    if s.out.exists() {
        s.finish()?;
        return completed_receipt(s);
    }
    let bytes = life::regular(&s.run.join("final.otf"))?;
    let (mut f, _) = kni_pipeline::otf_facts::read_otf(&bytes)?;
    let names = life::text(&s.run.join("names"))?
        .lines()
        .map(life::decode)
        .collect::<Result<Vec<_>, _>>()?;
    if names.len() != f.glyphs.len() {
        return Err("EXPORT_NAMES_COUNT".into());
    }
    for (g, n) in f.glyphs.iter_mut().zip(names) {
        g.name = n.clone();
        g.outline.glyph_id = n;
    }
    let map = life::text(&s.run.join("mapping"))?
        .lines()
        .map(|l| {
            let (c, g) = l.split_once('\t').ok_or("EXPORT_MAPPING")?;
            Ok((
                c.parse::<u32>().map_err(|_| "EXPORT_MAPPING")?,
                g.parse::<u16>().map_err(|_| "EXPORT_MAPPING")?,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;
    eprintln!("export_progress token={} slice_max_new=1", s.token());
    // An interrupted checkpoint may leave only its uncommitted staging file. The session lock
    // proves no live writer owns it; committed .glyph/context files are never removed here.
    let cache = s.run.join("cache");
    if cache.exists() {
        life::directory(&cache)?;
        for e in fs::read_dir(&cache).map_err(|e| e.to_string())? {
            let e = e.map_err(|e| e.to_string())?;
            let n = e.file_name().to_string_lossy().into_owned();
            if let Some((stem, pid)) = n.split_once(".tmp-") {
                if (stem == "context"
                    || stem.len() == 4 && stem.bytes().all(|b| b.is_ascii_digit()))
                    && !pid.is_empty()
                    && pid.bytes().all(|b| b.is_ascii_digit())
                {
                    let _ = life::regular(&e.path())?;
                    fs::remove_file(e.path()).map_err(|e| e.to_string())?;
                }
            }
        }
    }
    let (doc, rows) = match kni_pipeline::master_companion::build_checkpointed(
        &bytes,
        &f,
        &map,
        &s.run.join("cache"),
        &s.context,
        1,
    ) {
        Ok(x) => x,
        Err(e) if e.starts_with("MASTER_CHECKPOINT_PENDING ") => {
            return Err(format!("EXPORT_PENDING token={} {e}", s.run.display()))
        }
        Err(e) => return Err(e),
    };
    let build = s.run.join("publish");
    if build.exists() {
        life::directory(&build)?;
        fs::remove_dir_all(&build).map_err(|e| e.to_string())?;
    }
    fs::create_dir(&build).map_err(|e| e.to_string())?;
    for e in fs::read_dir(s.payload()).map_err(|e| e.to_string())? {
        let e = e.map_err(|e| e.to_string())?;
        life::exclusive(&build.join(e.file_name()), &life::regular(&e.path())?)?;
    }
    let name = life::text(&s.run.join("otf-name"))?;
    if name.contains(['/', '\\', '\n', '\t']) || name.is_empty() {
        return Err("EXPORT_OTF_NAME".into());
    }
    let master = name
        .strip_suffix(".otf")
        .ok_or("EXPORT_OTF_NAME")?
        .to_string()
        + ".glyphs";
    life::exclusive(
        &build.join("export-token"),
        s.run.to_string_lossy().as_bytes(),
    )?;
    life::exclusive(&build.join(&master), doc.as_bytes())?;
    life::exclusive(&build.join(&name), &bytes)?;
    if let Some((a, c)) = pins(&life::text(&s.run.join("provenance"))?)? {
        let (n, b) = k6_final_publish::build_sidecar_with_generated_master(
            &name,
            &bytes,
            &a,
            &c,
            Some((&master, doc.as_bytes())),
        )?;
        life::exclusive(&build.join(n), &b)?;
    }
    let receipt = life::text(&s.run.join("result-receipt"))?
        .replace(
            &s.payload().to_string_lossy().to_string(),
            &s.out.to_string_lossy(),
        )
        .replace(
            "master_export\tPENDING\tprivate_snapshot\ttrue\n",
            "master_export\tCOMPLETE\tprivate_snapshot\ttrue\n",
        )
        + &rows
        + &format!("master_glyphs_file\t{master}\nexport_lifecycle\tCOMPLETE\n");
    let receipt_name = fs::read_dir(&build)
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .map(|e| e.file_name())
        .find(|n| n.to_string_lossy().contains("receipt") && n.to_string_lossy().ends_with(".txt"));
    if let Some(n) = receipt_name {
        fs::remove_file(build.join(&n)).map_err(|e| e.to_string())?;
        life::exclusive(&build.join(n), receipt.as_bytes())?;
    }
    // Rebuild the detection-only run audit from completed payload, never publish the pending-stage audit.
    let audit = build.join(run_audit::RUN_AUDIT_FILENAME);
    if audit.exists() {
        fs::remove_file(&audit).map_err(|e| e.to_string())?;
    }
    let fields = life::text(&s.run.join("audit-identity"))?;
    let fields = fields
        .lines()
        .map(life::decode)
        .collect::<Result<Vec<_>, _>>()?;
    if fields.len() != 6 {
        return Err("EXPORT_AUDIT_IDENTITY".into());
    }
    run_audit::write_run_audit(
        &build,
        &run_audit::RunIdentity {
            population_sha256: fields[0].clone(),
            family: fields[1].clone(),
            subfamily: fields[2].clone(),
            postscript_name: fields[3].clone(),
            style_id: fields[4].clone(),
            emitter: fields[5].clone(),
        },
        if m.glyphs.is_empty() {
            run_audit::RunPath::PopulationFloor
        } else {
            run_audit::RunPath::Full
        },
    )
    .map_err(|e| e.to_string())?;
    s.commit(&build)?;
    s.finish()?;
    Ok(receipt)
}

fn completed_receipt(s: &life::Session) -> Result<String, String> {
    let n = fs::read_dir(&s.out)
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .find(|e| e.file_name().to_string_lossy().starts_with("receipt-"))
        .ok_or("EXPORT_RECEIPT_MISSING")?;
    life::text(&n.path())
}
