// Call sites land with briefs 5.2 (warn-export/degrade paths) and the
// population-floor path; until they land the public entry point has no
// non-test caller.
#![allow(dead_code)]

//! Run-failure receipt writer (brief 5.3; always-output rule,
//! docs/kni/2026-10-16-always-output-rule.md).
//!
//! When a run stops before the normal receipt bundle exists, the failed run
//! still owes a machine-readable record: the multi-style gate treats a style
//! without output as an engine defect, and the defect row must say WHY. This
//! module is the single writer of that record. The 5.2 warn-export/degrade
//! paths and the population-floor path call it; nothing else writes
//! `run-failure-receipt.txt`.
//!
//! Contract:
//! - `write_run_failure_receipt(out_dir, code, detail)` creates `out_dir`
//!   (with parents) when missing and writes `run-failure-receipt.txt` in it.
//! - `code` is a typed refusal/warning code: one stable SCREAMING_SNAKE
//!   token from the caller's own taxonomy. It is validated, never invented
//!   and never sanitized here; an invalid code is a caller defect and is
//!   refused.
//! - `detail` is free text from the caller; newlines and tabs collapse to
//!   spaces so the receipt stays one field per line.
//! - Create-new semantics: an existing `run-failure-receipt.txt` is never
//!   overwritten. A second failure record means a second attempt, and
//!   attempts never share an out_dir (the engine's own no-overwrite rule).
//! - Typed errors, no panics.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// File name of the run-failure receipt inside the run's out dir.
/// CONVENTION: kebab-case sibling of the normal run's `receipt.txt`; the
/// `run-failure-` prefix keeps a failed run's record unambiguous when an
/// out dir is inspected next to successful ones.
pub const RUN_FAILURE_RECEIPT_NAME: &str = "run-failure-receipt.txt";

/// Receipt format version row. CONVENTION: bump only on a layout change so
/// downstream readers can pin a parser to a version.
pub const RUN_FAILURE_RECEIPT_VERSION: u32 = 1;

#[derive(Debug)]
pub enum RunFailureReceiptError {
    /// `code` was empty or carried characters outside [A-Z0-9_]: a typed
    /// code is a caller contract, not free text.
    InvalidCode { code: String },
    /// A receipt already exists at the target; never overwritten.
    AlreadyExists { path: PathBuf },
    /// Filesystem failure with the failing operation named.
    Io { op: &'static str, source: io::Error },
}

impl std::fmt::Display for RunFailureReceiptError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RunFailureReceiptError::InvalidCode { code } => write!(
                f,
                "invalid typed code {code:?}: expected non-empty [A-Z0-9_]+"
            ),
            RunFailureReceiptError::AlreadyExists { path } => write!(
                f,
                "run-failure receipt already exists (no overwrite): {}",
                path.display()
            ),
            RunFailureReceiptError::Io { op, source } => {
                write!(f, "run-failure receipt {op}: {source}")
            }
        }
    }
}

impl std::error::Error for RunFailureReceiptError {}

fn validate_code(code: &str) -> Result<(), RunFailureReceiptError> {
    if !code.is_empty()
        && code
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_')
    {
        Ok(())
    } else {
        Err(RunFailureReceiptError::InvalidCode {
            code: code.to_string(),
        })
    }
}

/// One-line detail: CR/LF/TAB collapse to single spaces (receipt rows are
/// newline-delimited; a raw newline would forge extra rows).
fn collapse_detail(detail: &str) -> String {
    detail.split(|c| c == '\n' || c == '\r' || c == '\t')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Write the run-failure receipt for one failed run into `out_dir`.
/// Returns the written path on success.
pub fn write_run_failure_receipt(
    out_dir: &Path,
    code: &str,
    detail: &str,
) -> Result<PathBuf, RunFailureReceiptError> {
    validate_code(code)?;
    fs::create_dir_all(out_dir).map_err(|e| RunFailureReceiptError::Io {
        op: "create_dir_all",
        source: e,
    })?;
    let path = out_dir.join(RUN_FAILURE_RECEIPT_NAME);
    let body = format!(
        "run_failure_receipt\tversion\t{}\ncode\t{}\ndetail\t{}\n",
        RUN_FAILURE_RECEIPT_VERSION,
        code,
        collapse_detail(detail)
    );
    // create_new: the no-overwrite rule is enforced by the filesystem,
    // not by an exists() precheck (race).
    match fs::OpenOptions::new().write(true).create_new(true).open(&path) {
        Ok(mut f) => {
            use std::io::Write;
            f.write_all(body.as_bytes())
                .map_err(|e| RunFailureReceiptError::Io { op: "write", source: e })?;
        }
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
            return Err(RunFailureReceiptError::AlreadyExists { path });
        }
        Err(e) => {
            return Err(RunFailureReceiptError::Io { op: "create_new", source: e });
        }
    }
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "kni-run-failure-test-{}-{}",
            std::process::id(),
            tag
        ));
        let _ = fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn writes_version_code_detail_rows() {
        let d = tmp_dir("basic");
        let p = write_run_failure_receipt(&d, "SCALE_WIRING_REFUSED", "bad scale row").unwrap();
        assert_eq!(p, d.join(RUN_FAILURE_RECEIPT_NAME));
        let body = fs::read_to_string(&p).unwrap();
        assert_eq!(
            body,
            "run_failure_receipt\tversion\t1\ncode\tSCALE_WIRING_REFUSED\ndetail\tbad scale row\n"
        );
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn creates_missing_nested_out_dir() {
        let d = tmp_dir("nested").join("a/b/c");
        let p = write_run_failure_receipt(&d, "NOTDEF_REFUSED", "x").unwrap();
        assert!(p.is_file());
        let _ = fs::remove_dir_all(tmp_dir("nested"));
    }

    #[test]
    fn detail_newlines_and_tabs_collapse() {
        let d = tmp_dir("collapse");
        let p = write_run_failure_receipt(&d, "IO", "line one\nline two\tcol\r\nend").unwrap();
        let body = fs::read_to_string(&p).unwrap();
        assert_eq!(body.lines().count(), 3, "receipt stays three rows: {body:?}");
        assert!(body.contains("detail\tline one line two col end\n"));
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn invalid_codes_are_refused() {
        let d = tmp_dir("badcode");
        for bad in ["", "lowercase", "HAS SPACE", "Has-Dash", "tab\tcode"] {
            let e = write_run_failure_receipt(&d, bad, "x").unwrap_err();
            assert!(
                matches!(e, RunFailureReceiptError::InvalidCode { .. }),
                "{bad:?}: {e}"
            );
        }
        // Nothing written on refusal.
        assert!(!d.join(RUN_FAILURE_RECEIPT_NAME).exists());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn existing_receipt_is_never_overwritten() {
        let d = tmp_dir("overwrite");
        write_run_failure_receipt(&d, "FIRST_CODE", "first").unwrap();
        let e = write_run_failure_receipt(&d, "SECOND_CODE", "second").unwrap_err();
        assert!(matches!(e, RunFailureReceiptError::AlreadyExists { .. }), "{e}");
        let body = fs::read_to_string(d.join(RUN_FAILURE_RECEIPT_NAME)).unwrap();
        assert!(body.contains("code\tFIRST_CODE\n"), "original kept: {body:?}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn digits_and_underscores_are_valid_codes() {
        let d = tmp_dir("codes");
        for (i, ok) in ["V9R3_HARD_FAIL", "E5_2", "X"].iter().enumerate() {
            let sub = d.join(format!("{i}"));
            write_run_failure_receipt(&sub, ok, "d")
                .unwrap_or_else(|e| panic!("{ok:?} refused: {e}"));
        }
        let _ = fs::remove_dir_all(&d);
    }
}
