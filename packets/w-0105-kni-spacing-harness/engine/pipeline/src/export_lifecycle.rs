//! Private sealed export lifecycle. Snapshot files never become public individually.
use kni_core::cff_reader::sha256_hex;
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};
pub const EXIT_PENDING: u8 = 75;
pub fn hash(b: &[u8]) -> String {
    sha256_hex(b)
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub fn regular(p: &Path) -> Result<Vec<u8>, String> {
    let m = fs::symlink_metadata(p).map_err(err)?;
    if !m.is_file() || m.len() > 256 * 1024 * 1024 {
        return Err("EXPORT_UNSAFE_FILE".into());
    }
    fs::read(p).map_err(err)
}
pub fn directory(p: &Path) -> Result<(), String> {
    let m = fs::symlink_metadata(p).map_err(err)?;
    if !m.is_dir() {
        return Err("EXPORT_UNSAFE_DIR".into());
    }
    Ok(())
}
pub fn safe_mkdir(p: &Path) -> Result<(), String> {
    if fs::symlink_metadata(p).is_ok() {
        return directory(p);
    }
    if let Some(parent) = p.parent() {
        if !parent.as_os_str().is_empty() {
            safe_mkdir(parent)?;
        }
    }
    match fs::create_dir(p) {
        Ok(()) => sync_dir(p.parent().unwrap_or(Path::new("."))),
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => directory(p),
        Err(e) => Err(err(e)),
    }
}
pub fn sync_dir(p: &Path) -> Result<(), String> {
    fs::File::open(p).and_then(|f| f.sync_all()).map_err(err)
}
pub fn exclusive(p: &Path, b: &[u8]) -> Result<(), String> {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(err)?
        .as_nanos();
    let tmp = p.with_extension(format!("uncommitted-{}-{nonce}", std::process::id()));
    let mut f = fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&tmp)
        .map_err(err)?;
    let result = (|| {
        f.write_all(b).and_then(|_| f.sync_all()).map_err(err)?;
        fs::hard_link(&tmp, p).map_err(err)?;
        sync_dir(p.parent().ok_or("EXPORT_PARENT")?)
    })();
    let _ = fs::remove_file(tmp);
    result
}
pub fn text(p: &Path) -> Result<String, String> {
    String::from_utf8(regular(p)?).map_err(err)
}
pub fn hex(b: &[u8]) -> String {
    b.iter().map(|v| format!("{v:02x}")).collect()
}
pub fn unhex(s: &str) -> Result<Vec<u8>, String> {
    if s.len() % 2 != 0 || !s.is_ascii() {
        return Err("EXPORT_HEX".into());
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(err))
        .collect()
}
pub fn decode(s: &str) -> Result<String, String> {
    String::from_utf8(unhex(s)?).map_err(err)
}
pub fn tree_manifest(dir: &Path) -> Result<String, String> {
    directory(dir)?;
    let mut rows = Vec::new();
    for entry in fs::read_dir(dir).map_err(err)? {
        let e = entry.map_err(err)?;
        let n = e.file_name().into_string().map_err(|_| "EXPORT_NAME")?;
        if n.contains(['\n', '\t', '/']) {
            return Err("EXPORT_NAME".into());
        }
        let b = regular(&e.path())?;
        rows.push(format!(
            "{}\t{}\t{}\n",
            hex(n.as_bytes()),
            b.len(),
            hash(&b)
        ));
    }
    rows.sort();
    Ok(rows.concat())
}
pub fn verify(dir: &Path, expected: &str) -> Result<(), String> {
    if tree_manifest(dir)? != expected {
        return Err("EXPORT_SNAPSHOT_CORRUPT".into());
    }
    Ok(())
}
#[derive(Debug)]
pub enum Outcome {
    Pending(String),
    Complete(String),
}
#[derive(Clone, Debug)]
pub struct Session {
    pub run: PathBuf,
    pub out: PathBuf,
    pub context: String,
}
impl Session {
    pub fn open(
        root: &Path,
        style: &str,
        out: &Path,
        context: &str,
    ) -> Result<(Self, bool), String> {
        if style.is_empty()
            || !style
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        {
            return Err("EXPORT_STYLE".into());
        }
        safe_mkdir(root)?;
        let slot = root.join(format!("{style}.pending"));
        if slot.try_exists().map_err(err)? {
            let token = text(&slot)?;
            if token.len() != 64 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Err("EXPORT_SLOT_CORRUPT".into());
            }
            let run = root.join(&token);
            directory(&run)?;
            if text(&run.join("context"))? != context
                || decode(&text(&run.join("destination"))?)? != out.to_string_lossy()
            {
                return Err("PENDING_RUN_CONFLICT".into());
            }
            return Ok((
                Self {
                    run,
                    out: out.into(),
                    context: context.into(),
                },
                true,
            ));
        }
        if out.try_exists().map_err(err)? {
            return Err("EXPORT_DESTINATION_EXISTS".into());
        }
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(err)?
            .as_nanos();
        let token = hash(format!("{nonce}:{}:{context}", std::process::id()).as_bytes());
        let run = root.join(&token);
        fs::create_dir(&run).map_err(err)?;
        exclusive(&run.join("context"), context.as_bytes())?;
        exclusive(
            &run.join("destination"),
            hex(out.to_string_lossy().as_bytes()).as_bytes(),
        )?;
        exclusive(&run.join("style"), style.as_bytes())?;
        exclusive(&slot, token.as_bytes())?;
        Ok((
            Self {
                run,
                out: out.into(),
                context: context.into(),
            },
            false,
        ))
    }
    pub fn token(&self) -> String {
        self.run.file_name().unwrap().to_string_lossy().into()
    }
    pub fn payload(&self) -> PathBuf {
        self.run.join("payload")
    }
    pub fn seal(&self) -> Result<(), String> {
        for e in fs::read_dir(self.payload()).map_err(err)? {
            let p = e.map_err(err)?.path();
            let _ = regular(&p)?;
            fs::File::open(p).and_then(|f| f.sync_all()).map_err(err)?;
        }
        sync_dir(&self.payload())?;
        let m = tree_manifest(&self.payload())?;
        exclusive(&self.run.join("snapshot"), m.as_bytes())?;
        exclusive(&self.run.join("SEALED"), hash(m.as_bytes()).as_bytes())
    }
    pub fn verify(&self) -> Result<(), String> {
        directory(&self.run)?;
        let m = text(&self.run.join("snapshot"))?;
        if text(&self.run.join("SEALED"))? != hash(m.as_bytes()) {
            return Err("EXPORT_SEAL_CORRUPT".into());
        }
        verify(&self.payload(), &m)
    }
    pub fn lock(&self) -> Result<Lock, String> {
        let p = self.run.join("active");
        if fs::symlink_metadata(&p).is_ok() {
            let _ = regular(&p)?;
        }
        let f = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(p)
            .map_err(err)?;
        #[cfg(unix)]
        {
            use std::os::fd::AsRawFd;
            let rc = unsafe {
                extern "C" {
                    fn flock(fd: i32, op: i32) -> i32;
                }
                flock(f.as_raw_fd(), 2 | 4)
            };
            if rc != 0 {
                return Err("EXPORT_RUN_BUSY".into());
            }
        }
        #[cfg(not(unix))]
        {
            return Err("EXPORT_LOCK_UNSUPPORTED".into());
        }
        Ok(Lock(f))
    }
    pub fn commit(&self, build: &Path) -> Result<(), String> {
        let m = tree_manifest(build)?;
        exclusive(&self.run.join("complete-manifest"), m.as_bytes()).or_else(|e| {
            if text(&self.run.join("complete-manifest"))? == m {
                Ok(())
            } else {
                Err(e)
            }
        })?;
        exclusive(&build.join("COMPLETE"), hash(m.as_bytes()).as_bytes())?;
        sync_dir(build)?;
        rename_no_replace(build, &self.out)?;
        sync_dir(self.out.parent().ok_or("EXPORT_PARENT")?)?;
        self.verify_complete()?;
        Ok(())
    }
    pub fn verify_complete(&self) -> Result<(), String> {
        directory(&self.out)?;
        let m = text(&self.run.join("complete-manifest"))?;
        let seal = text(&self.out.join("COMPLETE"))?;
        if seal != hash(m.as_bytes()) {
            return Err("EXPORT_COMPLETE_CORRUPT".into());
        }
        let mut actual = tree_manifest(&self.out)?;
        let complete = regular(&self.out.join("COMPLETE"))?;
        let row = format!(
            "{}\t{}\t{}\n",
            hex(b"COMPLETE"),
            complete.len(),
            hash(&complete)
        );
        actual = actual.replace(&row, "");
        if actual != m {
            return Err("EXPORT_READBACK_CORRUPT".into());
        }
        Ok(())
    }
    pub fn finish(&self) -> Result<(), String> {
        self.verify_complete()?;
        let log = self.run.join("LOGGED");
        if !log.try_exists().map_err(err)? {
            exclusive(&log, format!("complete\t{}\n", self.token()).as_bytes())?;
        }
        let style = text(&self.run.join("style"))?;
        let slot = self.run.parent().unwrap().join(format!("{style}.pending"));
        if !slot.try_exists().map_err(err)? {
            return Ok(());
        }
        if text(&slot)? == self.token() {
            fs::remove_file(slot).map_err(err)?;
            sync_dir(self.run.parent().unwrap())?
        } else {
            return Err("EXPORT_SLOT_CONFLICT".into());
        }
        Ok(())
    }
}
pub struct Lock(fs::File);
impl Drop for Lock {
    fn drop(&mut self) {
        #[cfg(unix)]
        {
            use std::os::fd::AsRawFd;
            unsafe {
                extern "C" {
                    fn flock(fd: i32, op: i32) -> i32;
                }
                flock(self.0.as_raw_fd(), 8);
            }
        }
    }
}
pub fn rename_no_replace(from: &Path, to: &Path) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;
        let a = CString::new(from.as_os_str().as_bytes()).map_err(err)?;
        let b = CString::new(to.as_os_str().as_bytes()).map_err(err)?;
        #[cfg(target_os = "linux")]
        let rc = unsafe {
            extern "C" {
                fn renameat2(a: i32, b: *const i8, c: i32, d: *const i8, f: u32) -> i32;
            }
            renameat2(-100, a.as_ptr(), -100, b.as_ptr(), 1)
        };
        #[cfg(target_os = "macos")]
        let rc = unsafe {
            extern "C" {
                fn renamex_np(a: *const i8, b: *const i8, f: u32) -> i32;
            }
            renamex_np(a.as_ptr(), b.as_ptr(), 4)
        };
        if rc != 0 {
            return Err(format!(
                "EXPORT_COMMIT_REFUSED {}",
                std::io::Error::last_os_error()
            ));
        }
        Ok(())
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        let _ = (from, to);
        Err("EXPORT_ATOMIC_RENAME_UNSUPPORTED".into())
    }
}
