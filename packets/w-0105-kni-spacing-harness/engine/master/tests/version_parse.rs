//! The joint version-parse fixture (decision 2026-10-18, merged
//! slice C + slice D cases). One parser, `kni_master::version::parse_version`;
//! C and D call it, D-local parser retired.

use kni_master::version::parse_version;

#[test]
fn accept_cases() {
    // (input, expected)
    let cases: &[(&str, (u32, u32))] = &[
        ("Version 1.5", (1, 500)),
        ("Version 1.05", (1, 50)),
        ("1.050", (1, 50)),
        ("1.05", (1, 50)),
        ("1.005", (1, 5)),
        ("Version 2", (2, 0)),
        ("1.2 beta 3", (1, 200)),
        ("VERSION 2.050beta", (2, 50)),
        ("Version 10.25", (10, 250)),
        ("2.050", (2, 50)),
        ("Version 1.050", (1, 50)),
        ("Version 1.000", (1, 0)),
        ("version 2.0", (2, 0)),
        ("1.5", (1, 500)),
        ("2", (2, 0)),
        ("1.2beta7", (1, 200)),
        ("Version 1.050; build 7", (1, 50)),
        // Open case pinned whitespace-general per slice D: accept.
        ("Version 1.2\tbeta", (1, 200)),
    ];
    for (input, want) in cases {
        assert_eq!(parse_version(input), Some(*want), "accept {input:?}");
    }
}

#[test]
fn reject_cases() {
    for input in [
        "1.2.3", "1.2.3beta", "1.", "1.2345", "1.9999", "1.x", "x.1", "-1.2", "+1.2",
        "", "Version", "Version x.y", "1.2 3", "Versioned2",
    ] {
        assert_eq!(parse_version(input), None, "reject {input:?}");
    }
}
