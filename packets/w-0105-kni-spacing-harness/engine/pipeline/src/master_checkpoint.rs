//! Context-pinned optional checkpoint store for finalized native master glyphs.
use kni_core::{cff_container::CffGlyph, cff_reader::sha256_hex, native_font::NativeFontInput};
use kni_master::model::{MasterGlyph, Op};
use std::{
    io::Write,
    path::{Path, PathBuf},
};
const FORMAT: &str = "native-master-finalized-v1";
pub struct Checkpoint {
    dir: PathBuf,
    key: String,
}
fn file(path: &Path) -> Result<Option<Vec<u8>>, String> {
    match std::fs::symlink_metadata(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
        Ok(m) if !m.file_type().is_file() || m.len() > 64 * 1024 * 1024 => {
            Err("MASTER_CHECKPOINT_UNSAFE_FILE".into())
        }
        Ok(_) => std::fs::read(path).map(Some).map_err(|e| e.to_string()),
    }
}
fn exclusive(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let temp = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp)
        .map_err(|e| format!("MASTER_CHECKPOINT_WRITE {e}"))?;
    let result = (|| {
        f.write_all(bytes).map_err(|e| e.to_string())?;
        f.sync_all().map_err(|e| e.to_string())?;
        std::fs::hard_link(&temp, path).map_err(|e| e.to_string())
    })();
    let _ = std::fs::remove_file(temp);
    result
}
impl Checkpoint {
    pub fn open(
        dir: &Path,
        bytes: &[u8],
        prepared: &NativeFontInput,
        mapping: &[(u32, u16)],
        context: &str,
    ) -> Result<Self, String> {
        if context.len() != 64 || !context.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err("MASTER_CHECKPOINT_CONTEXT_HASH_REQUIRED".into());
        }
        if let Ok(m) = std::fs::symlink_metadata(dir) {
            if !m.file_type().is_dir() {
                return Err("MASTER_CHECKPOINT_UNSAFE_DIR".into());
            }
        }
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        let exe = std::fs::read(std::env::current_exe().map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        // Exact executable covers source, toolchain, native reader and all default parameters.
        // Final OTF covers outlines, metadata, GPOS/GSUB, names, widths and input lineage.
        let identity=format!("{FORMAT}\nfont={}\nexe={}\ncontext={}\nprepared={:?}\nmapping={mapping:?}\nprobe={:?}\n",sha256_hex(bytes),sha256_hex(&exe),context,prepared.glyphs.iter().map(|g|(&g.name,g.advance)).collect::<Vec<_>>(),std::env::var("PARTS_PROBE_GRID").ok());
        let key = sha256_hex(identity.as_bytes());
        let manifest = dir.join("context");
        match file(&manifest)? {
            Some(b) if b != identity.as_bytes() => {
                return Err("MASTER_CHECKPOINT_CONTEXT_MISMATCH".into())
            }
            Some(_) => {}
            None => {
                if std::fs::read_dir(dir)
                    .map_err(|e| e.to_string())?
                    .next()
                    .is_some()
                {
                    return Err("MASTER_CHECKPOINT_ORPHAN_DIR".into());
                }
                exclusive(&manifest, identity.as_bytes())?;
            }
        }
        for e in std::fs::read_dir(dir).map_err(|e| e.to_string())? {
            let e = e.map_err(|e| e.to_string())?;
            let n = e.file_name();
            let n = n.to_string_lossy();
            if n != "context"
                && !(n.len() == 10
                    && n.ends_with(".glyph")
                    && n[..4].bytes().all(|b| b.is_ascii_digit()))
            {
                return Err("MASTER_CHECKPOINT_UNKNOWN_FILE".into());
            }
        }
        for e in std::fs::read_dir(dir).map_err(|e| e.to_string())? {
            let name = e.map_err(|e| e.to_string())?.file_name();
            let name = name.to_string_lossy();
            if name != "context" {
                let gid = name[..4]
                    .parse::<usize>()
                    .map_err(|_| "MASTER_CHECKPOINT_UNKNOWN_FILE")?;
                if gid >= prepared.glyphs.len() {
                    return Err("MASTER_CHECKPOINT_GID_RANGE".into());
                }
            }
        }
        Ok(Self {
            dir: dir.into(),
            key,
        })
    }
    fn bind(&self, gid: usize, g: &CffGlyph, upm: f64) -> String {
        sha256_hex(
            format!(
                "{} gid={gid} name={} advance={} upm={:016x} source={:?}",
                self.key,
                g.name,
                g.advance,
                upm.to_bits(),
                g.outline
            )
            .as_bytes(),
        )
    }
    pub fn read(
        &self,
        gid: usize,
        g: &CffGlyph,
        upm: f64,
    ) -> Result<Option<(MasterGlyph, String)>, String> {
        let Some(b) = file(&self.dir.join(format!("{gid:04}.glyph")))? else {
            return Ok(None);
        };
        let text = std::str::from_utf8(&b).map_err(|_| "MASTER_CHECKPOINT_CORRUPT")?;
        let mut p = text.splitn(3, '\n');
        let binding = p.next().unwrap_or("");
        let hash = p.next().unwrap_or("");
        let payload = p.next().ok_or("MASTER_CHECKPOINT_CORRUPT")?;
        if binding != self.bind(gid, g, upm) || hash != sha256_hex(payload.as_bytes()) {
            return Err("MASTER_CHECKPOINT_CORRUPT_OR_BINDING".into());
        }
        let (fixture, ledger) = payload
            .split_once("\n#LEDGER\n")
            .ok_or("MASTER_CHECKPOINT_CORRUPT")?;
        let mut master = kni_master::fixture::parse(fixture)
            .map_err(|e| format!("MASTER_CHECKPOINT_CORRUPT {e}"))?;
        for c in &mut master.contours {
            let h = c
                .stroke
                .strip_prefix("hex")
                .ok_or("MASTER_CHECKPOINT_CORRUPT_STROKE")?;
            if h.len() % 2 != 0 {
                return Err("MASTER_CHECKPOINT_CORRUPT_STROKE".into());
            }
            let bytes = (0..h.len())
                .step_by(2)
                .map(|i| {
                    u8::from_str_radix(&h[i..i + 2], 16)
                        .map_err(|_| "MASTER_CHECKPOINT_CORRUPT_STROKE")
                })
                .collect::<Result<Vec<_>, _>>()?;
            c.stroke = String::from_utf8(bytes).map_err(|_| "MASTER_CHECKPOINT_CORRUPT_STROKE")?;
        }
        if master.name != g.name || master.advance != f64::from(g.advance) || master.upm != upm {
            return Err("MASTER_CHECKPOINT_GLYPH_MISMATCH".into());
        }
        Ok(Some((master, ledger.into())))
    }
    pub fn write(
        &self,
        gid: usize,
        g: &CffGlyph,
        upm: f64,
        m: &MasterGlyph,
        ledger: &str,
    ) -> Result<(), String> {
        if m.name.chars().any(char::is_whitespace)
            || m.contours
                .iter()
                .any(|c| c.stroke.chars().any(char::is_whitespace))
        {
            return Err("MASTER_CHECKPOINT_NAME_UNSUPPORTED".into());
        }
        let mut text = format!("glyph {} {} {}\n", m.name, m.advance, m.upm);
        for c in &m.contours {
            text.push_str(&format!(
                "stroke hex{}\n",
                c.stroke
                    .as_bytes()
                    .iter()
                    .map(|b| format!("{b:02x}"))
                    .collect::<String>()
            ));
            for op in &c.ops {
                text.push_str(&match op {
                    Op::Move(p) => format!("M {} {}\n", p.0, p.1),
                    Op::Line(p) => format!("L {} {}\n", p.0, p.1),
                    Op::Curve(a, b, c) => {
                        format!("C {} {} {} {} {} {}\n", a.0, a.1, b.0, b.1, c.0, c.1)
                    }
                    Op::Close => "Z\n".into(),
                });
            }
        }
        text.push_str("\n#LEDGER\n");
        text.push_str(ledger);
        let payload = format!(
            "{}\n{}\n{}",
            self.bind(gid, g, upm),
            sha256_hex(text.as_bytes()),
            text
        );
        exclusive(
            &self.dir.join(format!("{gid:04}.glyph")),
            payload.as_bytes(),
        )
    }
}
