//! The one shared font-version string parser for the kit. Items 16 (C)
//! and 17 (D) call this; no slice keeps a local parser.
//!
//! Grammar (decision 2026-10-18, merged with slice C/D fixture cases):
//! - optional case-insensitive `Version` prefix, which must be followed
//!   by whitespace (`Versioned2` is not a prefix, and parses as junk);
//! - `major`: unsigned decimal digits, no sign;
//! - optional fraction: `.` plus 1..=3 digits, read as a decimal fraction
//!   of one thousand: "1.5" -> (1,500), "1.05" -> (1,50), "1.005" -> (1,5),
//!   "1.050" -> (1,50), "1.000" -> (1,0);
//! - optional qualifier, dropped: after optional whitespace (any
//!   whitespace, tabs included) the qualifier may start with anything
//!   EXCEPT an ASCII digit or a dot, and may contain digits ("beta 3",
//!   "050beta", "; build 7"). A digit-led or dot-led remainder is not a
//!   qualifier, it is junk: "1.2 3", "1.2.3", "1.2.3beta" all reject.
//!
//! Rejected (`None`): "", "Version", "1.2.3", "1.2.3beta", "1.", "1.2345",
//! "1.9999", "1.x", "x.1", "-1.2", "+1.2", "Version x.y", "1.2 3",
//! "Versioned2".
//!
//! Comparison is numeric equality of the returned pair only; this
//! function makes no precedence or ordering claims. The caller retains
//! the raw string; only the pair is returned.

/// Parses a font version string into (major, minor-thousandths).
pub fn parse_version(raw: &str) -> Option<(u32, u32)> {
    let mut t = raw.trim();
    // Optional case-insensitive "Version" prefix, boundary-checked: it
    // must be followed by whitespace, otherwise it is not a prefix.
    if t.len() > 7 && t[..7].eq_ignore_ascii_case("version") && t.as_bytes()[7].is_ascii_whitespace() {
        t = t[7..].trim_start();
    }
    // Major: unsigned decimal digits only.
    let digits: usize = t.bytes().take_while(|b| b.is_ascii_digit()).count();
    if digits == 0 {
        return None;
    }
    let major: u32 = t[..digits].parse().ok()?;
    t = &t[digits..];
    // Optional fraction: '.' plus 1..=3 digits; a 4th digit is a reject.
    let mut minor: u32 = 0;
    if let Some(rest) = t.strip_prefix('.') {
        let fdigits: usize = rest.bytes().take_while(|b| b.is_ascii_digit()).count();
        if fdigits == 0 || fdigits > 3 {
            return None;
        }
        let frac: u32 = rest[..fdigits].parse().ok()?;
        minor = frac * 10u32.pow(3 - fdigits as u32);
        t = &rest[fdigits..];
    }
    // Optional qualifier, dropped: after optional whitespace it may start
    // with anything except an ASCII digit or a dot.
    let rest = t.trim_start();
    match rest.bytes().next() {
        None => Some((major, minor)),
        Some(b) if !b.is_ascii_digit() && b != b'.' => Some((major, minor)),
        Some(_) => None,
    }
}
