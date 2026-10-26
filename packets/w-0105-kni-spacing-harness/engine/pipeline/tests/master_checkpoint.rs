//! Bounded production checkpoint equivalence and fail-closed regression tests.
use kni_pipeline::{master_companion, otf_facts};
use std::path::{Path, PathBuf};
fn fixture() -> (
    Vec<u8>,
    kni_core::native_font::NativeFontInput,
    Vec<(u32, u16)>,
) {
    let bytes = include_bytes!("fixtures/master_checkpoint/mercator-four-real-glyph.otf").to_vec();
    let (mut f, m) = otf_facts::read_otf(&bytes).unwrap();
    let names = include_str!("fixtures/master_checkpoint/names.tsv");
    assert_eq!(names.lines().count(), f.glyphs.len());
    for (g, n) in f.glyphs.iter_mut().zip(names.lines()) {
        g.name = n.into();
        g.outline.glyph_id = n.into();
    }
    (bytes, f, m)
}

fn dir(tag: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("w2-cp-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    p
}
fn copy_dir(src: &Path, dst: &Path) {
    std::fs::create_dir(dst).unwrap();
    for e in std::fs::read_dir(src).unwrap() {
        let e = e.unwrap();
        std::fs::copy(e.path(), dst.join(e.file_name())).unwrap();
    }
}
#[test]
fn real_glyph_resume_byte_identical_and_context_corruption_refuse() {
    let (b, f, m) = fixture();
    let context = "a".repeat(64);
    let ordinary = master_companion::build(&b, &f, &m).unwrap().0;
    for slice in [1, 2] {
        let d = dir(&format!("slice{slice}"));
        let mut pending = 0;
        let doc = loop {
            match master_companion::build_checkpointed(&b, &f, &m, &d, &context, slice) {
                Ok((doc, _)) => break doc,
                Err(e) if e.starts_with("MASTER_CHECKPOINT_PENDING") => {
                    pending += 1;
                    assert!(pending < f.glyphs.len() + 1);
                }
                Err(e) => panic!("{e}"),
            }
        };
        assert_eq!(doc, ordinary, "sliced/unsliced exact document bytes");
        assert_eq!(
            master_companion::build_checkpointed(&b, &f, &m, &d, &context, 0)
                .unwrap()
                .0,
            ordinary,
            "all-hit resume no work permitted"
        );
        assert!(
            master_companion::build_checkpointed(&b, &f, &m, &d, &"b".repeat(64), 1)
                .unwrap_err()
                .contains("CONTEXT_MISMATCH")
        );
        let mut wrong = b.clone();
        wrong[12] ^= 1;
        assert!(
            master_companion::build_checkpointed(&wrong, &f, &m, &d, &context, 1)
                .unwrap_err()
                .contains("CONTEXT_MISMATCH")
        );
        let mut wrong_f = f.clone();
        wrong_f.glyphs[1].name.push('x');
        assert!(
            master_companion::build_checkpointed(&b, &wrong_f, &m, &d, &context, 1)
                .unwrap_err()
                .contains("CONTEXT_MISMATCH")
        );
        let c = dir(&format!("corrupt{slice}"));
        copy_dir(&d, &c);
        std::fs::write(c.join("0001.glyph"), b"corrupt").unwrap();
        assert!(
            master_companion::build_checkpointed(&b, &f, &m, &c, &context, 1)
                .unwrap_err()
                .contains("CORRUPT")
        );
        std::fs::remove_dir_all(c).unwrap();
        let c = dir(&format!("range{slice}"));
        copy_dir(&d, &c);
        std::fs::write(c.join("9999.glyph"), b"out-of-range").unwrap();
        assert!(
            master_companion::build_checkpointed(&b, &f, &m, &c, &context, 1)
                .unwrap_err()
                .contains("GID_RANGE")
        );
        std::fs::remove_dir_all(c).unwrap();
        let c = dir(&format!("unknown{slice}"));
        copy_dir(&d, &c);
        std::fs::write(c.join("unknown"), b"x").unwrap();
        assert!(
            master_companion::build_checkpointed(&b, &f, &m, &c, &context, 1)
                .unwrap_err()
                .contains("UNKNOWN_FILE")
        );
        std::fs::remove_dir_all(c).unwrap();
        #[cfg(unix)]
        {
            let c = dir(&format!("symlink{slice}"));
            copy_dir(&d, &c);
            std::fs::remove_file(c.join("0001.glyph")).unwrap();
            std::os::unix::fs::symlink(d.join("0001.glyph"), c.join("0001.glyph")).unwrap();
            assert!(
                master_companion::build_checkpointed(&b, &f, &m, &c, &context, 1)
                    .unwrap_err()
                    .contains("UNSAFE_FILE")
            );
            std::fs::remove_dir_all(c).unwrap();
        }
        std::fs::remove_dir_all(d).unwrap();
    }
}
